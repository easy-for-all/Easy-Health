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

    Response = Struct.new(:http_status, :body, keyword_init: true)

    def self.call(params:)
      new(params:).call
    end

    def initialize(params:)
      @params = params || {}
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

      reason = preference_skip_reason(user)
      if reason
        dispatch.update!(status: "skipped", skip_reason: reason)
        return skip(reason, dispatch:)
      end

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
        last_error_code: result.last_error_code
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
    def fcm_data(dispatch)
      {
        type: notification_type,
        notification_type: notification_type,
        target_path: route,
        route: route,
        correlation_id: dispatch.correlation_id,
        campaign_key: campaign_key.presence,
        dispatch_id: dispatch.id,
        source: "make"
      }.merge(extra_data).compact
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
      Response.new(
        http_status: :ok,
        body: { status: "skipped", reason: "orchestration_disabled", sent: false }
      )
    end

    def invalid_payload(reason)
      Response.new(
        http_status: :unprocessable_entity,
        body: { status: "skipped", reason: "invalid_payload", detail: reason, sent: false }
      )
    end

    def skip(reason, dispatch: nil, http_status: :ok)
      body = { status: "skipped", reason: reason, sent: false }
      body[:dispatch_id] = dispatch.id if dispatch
      Response.new(http_status: http_status, body: body)
    end

    def duplicate(dispatch)
      Response.new(
        http_status: :ok,
        body: { status: "duplicate", dispatch_id: dispatch.id, sent: false }
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
          sent: false
        }
      )
    end
  end
end
