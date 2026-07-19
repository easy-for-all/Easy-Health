module Make
  # Handles a push dispatch REQUESTED BY MAKE. Make orchestrates (when/if/which
  # template); this service is the technical gate + sender:
  #
  #   flag -> payload validation -> resolve user (by user_id, never token)
  #   -> idempotency -> preferences/opt-out/permission -> resolve tokens
  #   -> FcmDispatcher -> persist PushDispatch + audit -> structured response.
  #
  # EasyHealth (not Make) is the source of truth for consent: every send is
  # re-validated here regardless of what Make believes.
  class PushDispatchRequest
    # Versioned categories. Make only sends the notification_type; we decide if
    # that category may be delivered for this user.
    NOTIFICATION_CATEGORIES = %w[
      workout_reminder activation_reminder progress_update account_security transactional
    ].freeze

    # Categories gated by the functional workout-reminders opt-out.
    REMINDER_CATEGORIES = %w[workout_reminder activation_reminder].freeze

    # Engagement categories subject to the frequency cap + cooldown. progress_update
    # (first_workout_completed), transactional and account_security are exempt.
    ENGAGEMENT_CATEGORIES = %w[activation_reminder workout_reminder].freeze
    ENGAGEMENT_WEEKLY_CAP = 2
    ENGAGEMENT_WEEKLY_WINDOW = 7.days
    ENGAGEMENT_COOLDOWN = 20.hours

    # Route allowlist mirrored from web/src/shared/lib/push-deep-link.ts.
    ALLOWED_ROUTE_PREFIXES = %w[/workouts /workout /plan].freeze
    DEFAULT_ROUTE = "/workouts/ready".freeze

    TITLE_MAX = 120
    BODY_MAX = 240
    # Fields the client is NEVER allowed to set — a token must never come from Make.
    FORBIDDEN_FIELDS = %w[token device_token fcm_token tokens].freeze

    # Coarse per-user rate limit (DB-based; no Redis in this stack).
    RATE_LIMIT_PER_USER = ->(env) { env.presence&.to_i || 10 }
    RATE_LIMIT_WINDOW = 1.minute

    # --- Smoke-test bypass --------------------------------------------------
    # Production smoke tests need to fire the same event twice in a row, which
    # the 20h cooldown and the 2-per-7-days cap legitimately block. This bypass
    # waives ONLY those two frequency rules. Consent (push_enabled), category
    # opt-out, device permission, active token, route allowlist, payload
    # validation and Firebase config remain mandatory — they are never bypassed.
    #
    # Five independent conditions must ALL hold, so neither the production Make
    # scenario (which holds the dispatch bearer but not the test token) nor a
    # non-admin user can ever reach it:
    #   1. MAKE_PUSH_TEST_BYPASS_ENABLED explicitly on for the environment;
    #   2. a dedicated X-Push-Test-Token header matching
    #      MAKE_PUSH_TEST_BYPASS_TOKEN (verified in the controller, distinct
    #      from the dispatch bearer);
    #   3. data.source == "manual_push_test";
    #   4. data.bypass_engagement_frequency == true;
    #   5. the target user is an admin AND on the e-mail allowlist.
    BYPASS_SOURCE = "manual_push_test".freeze
    BYPASS_FLAG = "bypass_engagement_frequency".freeze
    DEFAULT_BYPASS_EMAILS = %w[mail.marcus.reis@gmail.com].freeze
    # Stripped from the outgoing FCM payload — test plumbing, not app data.
    BYPASS_DATA_KEYS = [ BYPASS_FLAG ].freeze

    Response = Struct.new(:http_status, :body, keyword_init: true)

    def self.call(params:, test_token_valid: false)
      new(params:, test_token_valid:).call
    end

    def initialize(params:, test_token_valid: false)
      @params = params || {}
      @test_token_valid = test_token_valid
    end

    def call
      return disabled unless orchestration_enabled?

      payload_error = payload_error_reason
      return invalid_payload(payload_error) if payload_error

      user = User.find_by(id: user_id)
      # user_not_found is returned as a neutral skip (200) to avoid user
      # enumeration — Make cannot tell "no such user" from "opted out".
      return skip("user_not_found") if user.nil?

      return skip("rate_limited", http_status: :too_many_requests) if rate_limited?(user)

      dispatch = resolve_dispatch(user)
      return duplicate(dispatch) if dispatch.delivered?

      reason = preference_skip_reason(user) || frequency_skip_reason(user)
      return skip_dispatch(user, dispatch, reason) if reason

      perform_dispatch(dispatch, user)
    rescue ActiveRecord::RecordNotUnique
      # Lost a concurrent create race — treat as duplicate.
      existing = PushDispatch.find_by(idempotency_key:)
      existing ? duplicate(existing) : skip("duplicate")
    end

    private

    attr_reader :params

    # --- Inputs -------------------------------------------------------------

    def user_id       = params[:user_id]
    def event_id      = params[:event_id].to_s
    def campaign_key  = params[:campaign_key].to_s
    def notification_type = params[:notification_type].to_s
    def title         = params[:title].to_s
    def body          = params[:body].to_s

    def route
      raw = params[:route].to_s
      raw.presence || DEFAULT_ROUTE
    end

    def idempotency_key
      [ event_id, campaign_key, user_id, notification_type ].join(":")
    end

    def correlation_id
      params[:correlation_id].presence || "make-#{event_id.presence || SecureRandom.hex(6)}"
    end

    # --- Validation ---------------------------------------------------------

    def payload_error_reason
      return "missing_user_id" if user_id.blank?
      return "unknown_notification_type" unless NOTIFICATION_CATEGORIES.include?(notification_type)
      return "missing_title" if title.blank?
      return "missing_body" if body.blank?
      return "title_too_long" if title.length > TITLE_MAX
      return "body_too_long" if body.length > BODY_MAX
      return "forbidden_token_field" if forbidden_field_present?
      return "unsafe_content" if unsafe_text?(title) || unsafe_text?(body)
      return "route_not_allowed" unless allowed_route?(route)

      nil
    end

    def forbidden_field_present?
      keys = params.respond_to?(:keys) ? params.keys.map(&:to_s) : []
      data_keys = extra_data_source.keys.map(&:to_s)
      (keys + data_keys).any? { |k| FORBIDDEN_FIELDS.include?(k) }
    end

    # Block HTML tags and javascript: URLs in user-visible copy.
    def unsafe_text?(text)
      text.match?(/<[^>]+>/) || text.match?(/javascript:/i)
    end

    def allowed_route?(path)
      return false unless safe_internal_path?(path)

      ALLOWED_ROUTE_PREFIXES.any? { |prefix| path == prefix || path.start_with?("#{prefix}/") }
    end

    def safe_internal_path?(path)
      return false unless path.is_a?(String) && path.present?
      return false unless path.start_with?("/")
      return false if path.start_with?("//")
      return false if path.include?("://")
      return false if path.match?(/[\n\r\t\\]/)

      true
    end

    # --- Idempotency --------------------------------------------------------

    def resolve_dispatch(user)
      dispatch = PushDispatch.find_or_initialize_by(idempotency_key:)
      return dispatch if dispatch.persisted?

      dispatch.assign_attributes(
        event_id: event_id.presence,
        user: user,
        campaign_key: campaign_key.presence,
        notification_type: notification_type,
        title: title,
        body: body,
        route: route,
        correlation_id: correlation_id,
        requested_by: "make",
        requested_at: Time.current,
        status: "received",
        payload_json: safe_payload
      )
      dispatch.save!
      dispatch
    end

    # Persisted context for audit — MUST NOT contain a device token.
    def safe_payload
      { "route" => route, "campaign_key" => campaign_key.presence, "data" => extra_data }.compact
    end

    # --- Preferences / opt-out ---------------------------------------------

    def preference_skip_reason(user)
      prefs = user.notification_preferences
      return "global_opt_out" if prefs.nil? || !prefs.push_enabled? || prefs.notifications_disabled_at.present?
      return "category_opt_out" if REMINDER_CATEGORIES.include?(notification_type) && !prefs.workout_reminders_enabled?

      active_tokens = user.device_tokens.active
      return "no_active_token" unless active_tokens.exists?
      # A token registered with an explicit non-granted permission is not deliverable.
      return "permission_denied" unless active_tokens.where(permission_status: [ nil, "granted" ]).exists?

      nil
    end

    # --- Frequency (engagement only, reuses push_dispatches) ----------------

    def frequency_skip_reason(user)
      return nil unless engagement_category?
      return nil if frequency_bypassed?(user)

      delivered = PushDispatch
                  .where(user_id: user.id, notification_type: ENGAGEMENT_CATEGORIES,
                         status: PushDispatch::DELIVERED_STATUSES)

      return "cooldown_active" if delivered.where("dispatched_at > ?", ENGAGEMENT_COOLDOWN.ago).exists?
      return "frequency_capped" if delivered.where("dispatched_at > ?", ENGAGEMENT_WEEKLY_WINDOW.ago).count >= ENGAGEMENT_WEEKLY_CAP

      nil
    end

    def engagement_category?
      ENGAGEMENT_CATEGORIES.include?(notification_type)
    end

    # True only when every one of the five conditions documented on BYPASS_SOURCE
    # holds. Memoised because it both gates the frequency rules and is reported
    # in the response/audit trail.
    def frequency_bypassed?(user)
      return @frequency_bypassed unless @frequency_bypassed.nil?

      @frequency_bypassed = evaluate_bypass(user)
    end

    def evaluate_bypass(user)
      return false unless bypass_requested?

      # From here on the caller ASKED for a bypass — every outcome is audited,
      # including refusals, so an attempt by a non-admin is visible.
      unless bypass_enabled_for_env?
        return audit_bypass(user, granted: false, reason: "bypass_disabled_for_env")
      end
      unless @test_token_valid
        return audit_bypass(user, granted: false, reason: "invalid_test_token")
      end
      unless bypass_allowed_user?(user)
        return audit_bypass(user, granted: false, reason: "user_not_allowlisted")
      end

      audit_bypass(user, granted: true, reason: nil)
    end

    def bypass_requested?
      raw = extra_data_source[BYPASS_FLAG] || extra_data_source[BYPASS_FLAG.to_sym]
      return false unless ActiveModel::Type::Boolean.new.cast(raw)

      source = (extra_data_source["source"] || extra_data_source[:source]).to_s
      source == BYPASS_SOURCE
    end

    def bypass_enabled_for_env?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("MAKE_PUSH_TEST_BYPASS_ENABLED", "false"))
    end

    # Admin flag AND e-mail allowlist — either one alone is not enough.
    def bypass_allowed_user?(user)
      return false unless user.admin?

      user.email.to_s.downcase.in?(bypass_allowed_emails)
    end

    def bypass_allowed_emails
      configured = ENV["MAKE_PUSH_TEST_BYPASS_EMAILS"].to_s.split(",").map { |e| e.strip.downcase }.reject(&:blank?)
      (configured.presence || DEFAULT_BYPASS_EMAILS).map(&:downcase)
    end

    # Every bypass attempt lands in the log AND in user_events. Returns `granted`
    # so callers can use it as the predicate value directly.
    def audit_bypass(user, granted:, reason:)
      Rails.logger.warn(
        "[Make::PushDispatches] engagement frequency bypass #{granted ? 'GRANTED' : 'DENIED'} " \
        "user_id=#{user.id} admin=#{user.admin?} campaign_key=#{campaign_key.presence.inspect} " \
        "notification_type=#{notification_type} correlation_id=#{correlation_id}#{reason ? " denied_reason=#{reason}" : ''}"
      )
      UserEventService.track(
        user: user,
        event_name: granted ? "push_frequency_bypass_granted" : "push_frequency_bypass_denied",
        metadata: {
          notification_type: notification_type,
          campaign_key: campaign_key.presence,
          correlation_id: correlation_id,
          denied_reason: reason
        }.compact,
        source: "make_push",
        suppress_make_delivery: true
      )
      granted
    end

    # Persist the skip on the dispatch, emit the funnel analytics, return the
    # structured skip response.
    def skip_dispatch(user, dispatch, reason)
      dispatch.update!(status: "skipped", skip_reason: reason)
      PushJourney.track_dispatch_skipped(
        user: user,
        event_name: data_event_name,
        metadata: {
          skip_reason: reason, notification_type: notification_type,
          campaign_key: campaign_key.presence, dispatch_id: dispatch.id,
          correlation_id: dispatch.correlation_id
        }
      )
      skip(reason, dispatch: dispatch)
    end

    def data_event_name
      (extra_data_source["event_name"] || extra_data_source[:event_name]).to_s.presence || campaign_key.presence
    end

    # --- Send ---------------------------------------------------------------

    def perform_dispatch(dispatch, user)
      dispatch.update!(status: "processing")

      result = PushNotifications::FcmDispatcher.new.call(
        user: user,
        title: title,
        body: body,
        data: fcm_data(dispatch),
        notification_type: notification_type,
        correlation_id: dispatch.correlation_id
      )

      dispatch.update!(
        status: dispatch_status(result),
        dispatched_at: Time.current,
        provider_accepted_at: (result.sent? ? Time.current : nil),
        tokens_attempted_count: result.tokens_attempted,
        tokens_accepted_count: result.tokens_accepted,
        tokens_rejected_count: result.tokens_rejected,
        last_error_code: result.last_error_code,
        last_error_message: result.last_error_message
      )

      emit_audit(user, dispatch, result)

      result.sent? ? accepted_response(dispatch, result) : failed_response(dispatch, result)
    end

    def dispatch_status(result)
      return "failed" unless result.sent?

      result.partial? ? "partially_accepted" : "provider_accepted"
    end

    # `route` is exposed to the app as `target_path` — that is the field the
    # deep-link resolver reads. All FCM data values become strings downstream.
    #
    # Keys MUST all be strings: FCM's `data` is a map<string,string> and a Ruby
    # hash mixing :source and "source" serializes to a DUPLICATE JSON key, which
    # FCM rejects with INVALID_ARGUMENT ("Repeated map key"). Make's arbitrary
    # data is the base; our reserved keys override it so a scenario can never
    # clobber tracking/deep-link fields.
    def fcm_data(dispatch)
      extra_data.except(*BYPASS_DATA_KEYS).merge(
        "type" => notification_type,
        "notification_type" => notification_type,
        "target_path" => route,
        "route" => route,
        "correlation_id" => dispatch.correlation_id,
        "campaign_key" => campaign_key.presence,
        "dispatch_id" => dispatch.id.to_s,
        "source" => "make"
      ).compact
    end

    # Allowlisted extra data from Make. Strings only; forbidden keys are stripped.
    def extra_data
      extra_data_source.each_with_object({}) do |(k, v), acc|
        key = k.to_s
        next if FORBIDDEN_FIELDS.include?(key)
        next if v.is_a?(Hash) || v.is_a?(Array)

        acc[key] = v.to_s
      end
    end

    def extra_data_source
      raw = params[:data]
      raw.respond_to?(:to_h) ? raw.to_h : {}
    end

    def emit_audit(user, dispatch, result)
      base = {
        dispatch_id: dispatch.id,
        campaign_key: campaign_key.presence,
        notification_type: notification_type,
        correlation_id: dispatch.correlation_id,
        source: "make"
      }
      result.outcomes.each do |outcome|
        UserEventService.track(
          user: user,
          event_name: outcome.result.sent? ? "push_provider_accepted" : "push_provider_rejected",
          metadata: base.merge(
            provider_message_id: outcome.result.message_id,
            error_code: outcome.result.error_code,
            device_digest: device_digest(outcome.device.token)
          ),
          source: "make_push",
          suppress_make_delivery: true
        )
      end
    end

    def device_digest(token)
      return nil if token.blank?

      Digest::SHA256.hexdigest(token)[0, 12]
    end

    # --- Rate limiting ------------------------------------------------------

    def rate_limited?(user)
      limit = RATE_LIMIT_PER_USER.call(ENV["MAKE_PUSH_RATE_LIMIT_PER_USER"])
      return false if limit <= 0

      PushDispatch.where(user_id: user.id)
                  .where("created_at > ?", RATE_LIMIT_WINDOW.ago)
                  .count >= limit
    end

    # --- Config -------------------------------------------------------------

    def orchestration_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("MAKE_PUSH_ORCHESTRATION_ENABLED", "false"))
    end

    # --- Responses ----------------------------------------------------------

    def disabled
      skip("orchestration_disabled")
    end

    def invalid_payload(reason)
      # `detail` is kept for backwards compatibility with the existing Make
      # scenario; skip_reason carries the specific validation failure.
      skip("invalid_payload", http_status: :unprocessable_entity, extra: { detail: reason })
    end

    # Canonical skip envelope. Every non-send answer goes through here so an
    # operator can always read WHY from a single field, plus enough context
    # (dispatch/type/campaign) to find the row without another query.
    #
    # `reason` is a deprecated alias of `skip_reason`, kept so existing Make
    # scenarios and dashboards do not break on this change.
    def skip(reason, dispatch: nil, http_status: :ok, extra: {})
      body = {
        status: "skipped",
        sent: false,
        skip_reason: reason,
        reason: reason,
        dispatch_id: dispatch&.id,
        notification_type: notification_type.presence,
        campaign_key: campaign_key.presence,
        correlation_id: correlation_id
      }.merge(extra).compact
      Response.new(http_status: http_status, body: body)
    end

    def duplicate(dispatch)
      Response.new(
        http_status: :ok,
        body: {
          status: "duplicate",
          sent: false,
          skip_reason: "duplicate",
          reason: "duplicate",
          dispatch_id: dispatch.id,
          notification_type: notification_type.presence,
          campaign_key: campaign_key.presence,
          correlation_id: dispatch.correlation_id
        }.compact
      )
    end

    def accepted_response(dispatch, result)
      Response.new(
        http_status: :ok,
        body: {
          status: dispatch.status,
          dispatch_id: dispatch.id,
          correlation_id: dispatch.correlation_id,
          tokens_attempted: result.tokens_attempted,
          tokens_accepted: result.tokens_accepted,
          tokens_rejected: result.tokens_rejected,
          sent: true
        }
      )
    end

    # Provider send failed with no accepted token. 502 lets the Make Error
    # Handler retry; a later retry re-dispatches the same (non-delivered) row.
    def failed_response(dispatch, result)
      Response.new(
        http_status: :bad_gateway,
        body: {
          status: "failed",
          dispatch_id: dispatch.id,
          last_error_code: result.last_error_code,
          last_error_message: result.last_error_message,
          sent: false
        }
      )
    end
  end
end
