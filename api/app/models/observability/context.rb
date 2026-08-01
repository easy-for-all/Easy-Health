module Observability
  # Per-request (and per-job) correlation context.
  #
  # Populated by ObservabilityRequestContext (Rack middleware) for HTTP, by
  # ObservabilityInstrumented for jobs, and by `.for_task` for rake tasks, so
  # that a log line, an analytics event, a Sentry tag and an incident can all be
  # tied back to the same request_id without threading arguments through every
  # service.
  #
  # SECURITY: every value that arrives from a header is client-controlled. It is
  # sanitized by Observability::Headers before it lands here and it is NEVER
  # used for authorization — Devise and `require_admin!` remain the only
  # authority. Raw installation_id/session_id stay in-process for DB lookups;
  # anything leaving the process uses the hashed *_ref accessors.
  class Context < ActiveSupport::CurrentAttributes
    attribute :request_id, :trace_id
    attribute :installation_id, :session_id, :user_id
    attribute :platform, :app_version, :app_build
    attribute :environment, :route, :controller, :action
    attribute :auth_flow, :source, :job_key, :integration_key
    attribute :started_at

    REF_LENGTH = 16

    class << self
      # Internal primary key only. Never an email, name or external id.
      def user_ref
        id = user_id
        id.presence && "u_#{id}"
      end

      def installation_ref
        digest_ref("ins", installation_id)
      end

      def session_ref
        digest_ref("ses", session_id)
      end

      # nil rather than "unknown" when no build was reported at all: a log line
      # should not claim a cohort it never observed. Web traffic simply has no
      # build, and that is not the same as an unparseable one.
      def build_group
        return nil if app_build.blank?

        Observability::BuildGroup.for(app_build)
      end

      # Tags attached to every Sentry event. Refs only — see the class comment.
      def sentry_tags
        {
          request_id: request_id,
          trace_id: trace_id,
          platform: platform,
          app_version: app_version,
          app_build: app_build,
          build_group: build_group,
          route: route,
          auth_flow: auth_flow,
          source: source,
          job_key: job_key,
          installation_ref: installation_ref,
          environment: environment || Rails.env.to_s
        }.compact_blank
      end

      # Fields shared by every structured log line and every server-side event.
      def to_log_context
        {
          request_id: request_id,
          trace_id: trace_id,
          user_ref: user_ref,
          installation_ref: installation_ref,
          session_ref: session_ref,
          platform: platform,
          app_version: app_version,
          app_build: app_build,
          build_group: build_group,
          route: route,
          controller: controller,
          action: action,
          auth_flow: auth_flow,
          source: source,
          job_key: job_key,
          integration_key: integration_key,
          environment: environment || Rails.env.to_s
        }
      end

      # Safe properties for ProductAnalyticsEvent. No refs that could be joined
      # back to a person outside this system, no free text.
      #
      # installation_id is raw here, and only here. product_analytics_events is
      # our own table in our own database, and the raw id is what lets a server
      # event (google_auth_started, installation_link_succeeded) sit on the same
      # timeline as the client events that carry it — the hashed ref cannot be
      # joined to app_installations. It identifies an installation, never a
      # person. Everything that LEAVES the process (logs, Sentry) keeps using
      # installation_ref.
      def to_event_properties
        {
          request_id: request_id,
          platform: platform,
          app_version: app_version,
          app_build: app_build,
          build_group: build_group,
          installation_id: installation_id
        }.compact_blank
      end

      # Wraps a rake task / runner script so its work is correlated the same way
      # an HTTP request is. Always resets, even on raise.
      def for_task(key, source: "rake")
        reset
        self.source = source
        self.job_key = key.to_s
        self.environment = Rails.env.to_s
        self.request_id = "task-#{SecureRandom.hex(8)}"
        self.trace_id = request_id
        self.started_at = Time.current
        yield
      ensure
        reset
      end

      private

      # Stable, non-reversible reference for an external identifier. Stable so
      # the same device correlates across log lines; hashed so the raw id never
      # reaches an external sink.
      def digest_ref(prefix, value)
        raw = value.presence
        return nil if raw.nil?

        digest = OpenSSL::HMAC.hexdigest("SHA256", Observability::Config.hash_salt, raw.to_s)
        "#{prefix}_#{digest[0, REF_LENGTH]}"
      rescue StandardError
        nil
      end
    end
  end
end
