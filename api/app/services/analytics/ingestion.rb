module Analytics
  # Ingests a batch of product analytics events from the frontend.
  #
  # Responsibilities:
  #   - validate names/versions against the canonical taxonomy
  #   - only persist events whose sink includes "server"
  #   - sanitize properties (strip known sensitive keys)
  #   - idempotency via idempotency_key (duplicates are no-ops)
  #   - stamp received_at server-side
  #   - set users.activation_platform on the first event of a known user
  #   - record analytics_event_rejected for unknown events (no sensitive payload)
  #
  # Never raises to the caller for a single bad event — a failing event must not
  # drop the rest of the batch nor break the client.
  class Ingestion
    MAX_BATCH_SIZE = 50
    MAX_PROPERTIES_BYTES = 8_192
    AUTH_PROVIDER_CLICKED_ENUMS = {
      "provider" => %w[google email],
      "auth_screen" => %w[sign_up login],
      "intent" => %w[sign_up login],
      "source" => %w[auth_screen]
    }.freeze

    # failure_category is a DIMENSION, so it must be a closed vocabulary: a value
    # outside this list is dropped, never "cleaned up and kept". The device is
    # the one choosing the string, and one stray plugin message turning into a
    # dimension value is how a panel starts growing rows nobody can group by.
    FAILURE_CATEGORIES = %w[
      user_cancelled provider_error oauth_configuration_error network_error
      timeout backend_error invalid_credentials validation_error rate_limited unknown
    ].freeze

    # Events allowed to carry failure_category. Anywhere else the key is simply
    # not part of the contract.
    FAILURE_CATEGORY_EVENTS = %w[social_login_failed auth_client_error auth_api_error].freeze

    # One authentication attempt. Opaque, random and client-minted, so it is
    # bounded exactly like the correlation headers are.
    ATTEMPT_ID_PATTERN = /\A[A-Za-z0-9._:-]{1,64}\z/

    Result = Struct.new(:accepted, :persisted, :skipped, :rejected, :rejections, keyword_init: true)

    def self.enabled?
      ENV.fetch("ANALYTICS_INGESTION_ENABLED", "true") != "false"
    end

    def initialize(user:, events:)
      @user = user
      @events = Array(events).first(MAX_BATCH_SIZE)
      @result = Result.new(accepted: 0, persisted: 0, skipped: 0, rejected: 0, rejections: [])
    end

    def call
      return @result unless self.class.enabled?

      @events.each { |raw| process(raw) }
      set_activation_platform!
      @result
    end

    private

    def process(raw)
      attrs = normalize(raw)
      name = attrs[:event_name]

      unless EventCatalog.known?(name)
        reject!(name, "unknown_event")
        return
      end

      @result.accepted += 1

      # Only server-sink events are persisted; ga4/clarity-only events reaching
      # this endpoint are accepted and ignored (the frontend should not send them).
      unless EventCatalog.server_tracked.include?(name)
        @result.skipped += 1
        return
      end

      persist(attrs)
    end

    def persist(attrs)
      ProductAnalyticsEvent.create!(attrs.merge(received_at: Time.current))
      @result.persisted += 1
    rescue ActiveRecord::RecordNotUnique
      # Duplicate idempotency_key — no-op, exactly-once semantics.
      @result.skipped += 1
    rescue ActiveRecord::RecordInvalid => e
      reject!(attrs[:event_name], "invalid: #{e.record.errors.full_messages.first}")
    end

    def normalize(raw)
      h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      h = h.symbolize_keys
      name = h[:event_name].to_s

      {
        event_name: name,
        event_version: coerce_version(h[:event_version], name),
        occurred_at: parse_time(h[:occurred_at]) || Time.current,
        user_id: @user&.id,
        anonymous_id: presence(h[:anonymous_id]),
        session_id: presence(h[:session_id]),
        platform: enum(h[:platform], EventCatalog::PLATFORMS),
        app_surface: enum(h[:app_surface], EventCatalog::APP_SURFACES),
        app_version: presence(h[:app_version]),
        build_number: presence(h[:build_number]),
        environment: enum(h[:environment], EventCatalog::ENVIRONMENTS, default: "production"),
        locale: presence(h[:locale]),
        timezone: presence(h[:timezone]),
        source: presence(h[:source]),
        properties: with_installation_id(filtered_properties(name, h[:properties])),
        idempotency_key: presence(h[:idempotency_key])
      }
    end

    # Without this, an anonymous pre-auth event can never be joined to the
    # app_installations row that produced it — the gap that made an Android
    # install a black box until it authenticated.
    #
    # The client already puts it in the body (analytics/server.ts). The header is
    # the fallback for the path the body cannot cover reliably, and it never
    # overwrites a value the client sent: the two agree, and a batch flushed by
    # sendBeacon carries the body but no headers at all.
    def with_installation_id(properties)
      return properties if properties["installation_id"].present?

      from_context = Observability::Context.installation_id.presence
      return properties if from_context.blank?

      properties.merge("installation_id" => from_context)
    rescue StandardError
      properties
    end

    def filtered_properties(event_name, value)
      clean = sanitized_properties(value)
      return auth_provider_clicked_properties(clean) if event_name == "auth_provider_clicked"

      guard_failure_category(event_name, guard_auth_attempt_id(clean))
    end

    def auth_provider_clicked_properties(properties)
      out = {}

      AUTH_PROVIDER_CLICKED_ENUMS.each do |key, allowed|
        value = properties[key].to_s
        out[key] = value if allowed.include?(value)
      end

      if out["auth_screen"] == "sign_up" && boolean_property?(properties["terms_accepted"])
        out["terms_accepted"] = properties["terms_accepted"]
      end

      installation_id = properties["installation_id"].to_s.presence
      out["installation_id"] = installation_id if installation_id
      # This event builds a NEW hash from an allow-list, so anything not named
      # here is dropped — including the attempt id, which is the only thing that
      # ties this click to the failure or the success that followed it.
      attempt_id = auth_attempt_id(properties)
      out["auth_attempt_id"] = attempt_id if attempt_id
      out
    end

    def guard_auth_attempt_id(properties)
      return properties unless properties.key?("auth_attempt_id")

      attempt_id = auth_attempt_id(properties)
      return properties.merge("auth_attempt_id" => attempt_id) if attempt_id

      properties.except("auth_attempt_id")
    end

    def guard_failure_category(event_name, properties)
      return properties unless properties.key?("failure_category")

      value = properties["failure_category"].to_s
      return properties.merge("failure_category" => value) if
        FAILURE_CATEGORY_EVENTS.include?(event_name) && FAILURE_CATEGORIES.include?(value)

      properties.except("failure_category")
    end

    def auth_attempt_id(properties)
      value = properties["auth_attempt_id"].to_s.strip
      value.match?(ATTEMPT_ID_PATTERN) ? value : nil
    end

    def boolean_property?(value)
      value == true || value == false
    end

    def sanitized_properties(value)
      hash = value.is_a?(Hash) ? value : {}
      clean = RelationshipEventTracker.sanitize_metadata(hash)
      # Guard against oversized payloads.
      return {} if clean.to_json.bytesize > MAX_PROPERTIES_BYTES

      clean
    rescue StandardError
      {}
    end

    def set_activation_platform!
      return unless @user && @user.activation_platform.blank?

      platform = @events.map { |e| e.is_a?(Hash) || e.respond_to?(:to_unsafe_h) ? normalize(e)[:platform] : nil }
                        .compact.reject { |p| p == "unknown" }.first
      return if platform.blank?

      @user.update_column(:activation_platform, platform)
    rescue StandardError => e
      Rails.logger.warn("[analytics] activation_platform update failed: #{e.class}")
    end

    def reject!(name, reason)
      @result.rejected += 1
      @result.rejections << { event_name: name.to_s[0, 64], reason: reason }
      # Record for the Data Quality dashboard — never carries the original payload.
      ProductAnalyticsEvent.create!(
        event_name: "analytics_event_rejected",
        event_version: 1,
        occurred_at: Time.current,
        received_at: Time.current,
        user_id: @user&.id,
        platform: "unknown",
        app_surface: "unknown",
        environment: Rails.env.to_s,
        properties: { rejected_event_name: name.to_s[0, 64], reason: reason }
      )
    rescue StandardError => e
      Rails.logger.warn("[analytics] reject logging failed: #{e.class}")
    end

    def coerce_version(value, name)
      value.presence&.to_i || EventCatalog.current_version(name) || 1
    end

    def enum(value, allowed, default: "unknown")
      allowed.include?(value.to_s) ? value.to_s : default
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def presence(value)
      value.to_s.presence
    end
  end
end
