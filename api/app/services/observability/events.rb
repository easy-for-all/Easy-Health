module Observability
  # The single call site for every observability-relevant event.
  #
  # Each method fans out to both sinks that must agree:
  #   1. Observability::Logger  — structured JSON line, for log search
  #   2. Analytics::ServerEvents — a row in product_analytics_events, which is
  #      what the health checks actually query and what reaches the BI replica
  #
  # They are fanned out here, once, rather than at each call site, because the
  # moment a controller logs one thing and records another the checks start
  # disagreeing with the logs and nobody can tell which is lying. (A metrics
  # sink is intended to join this list; adding it must not touch callers.)
  #
  # PRIVACY: every property below is an enum, a boolean, a count or an already
  # hashed ref. No email, no token, no name, no free-text error message. Error
  # detail belongs in Sentry, which has the exception object and the scrubbing
  # to go with it.
  module Events
    # Closed vocabulary. A code outside this list is coerced to "internal_error"
    # so a stray exception message can never become a new dimension value.
    AUTH_ERROR_CODES = %w[
      invalid_token
      invalid_audience
      consent_required
      account_deleted
      provider_error
      internal_error
    ].freeze

    AUTH_FLOWS   = %w[native web web_mobile].freeze
    AUTH_INTENTS = %w[login sign_up unknown].freeze

    LINK_RESULTS = %w[linked already_linked conflict not_found error].freeze

    module_function

    # ── Google authentication ────────────────────────────────────────────────

    def google_auth_started(flow:, intent: nil, terms_accepted: nil)
      emit(
        "google_auth_started",
        level: :info,
        result: "started",
        properties: {
          auth_flow: normalize_flow(flow),
          auth_provider: "google",
          auth_intent: normalize_intent(intent),
          terms_accepted: boolean_or_nil(terms_accepted)
        }
      )
    end

    def google_auth_succeeded(flow:, user: nil, new_user: nil, intent: nil)
      emit(
        "google_auth_succeeded",
        level: :info,
        user: user,
        result: "success",
        properties: {
          auth_flow: normalize_flow(flow),
          auth_provider: "google",
          auth_intent: normalize_intent(intent),
          new_user: boolean_or_nil(new_user),
          installation_present: Observability::Context.installation_id.present?
        }
      )
    end

    # `terms_accepted` is what separates an expected consent_required (the user
    # signed in to an account that does not exist yet) from a real bug (the
    # client already collected consent and the server still refused). The
    # google_auth_consent_anomaly check reads exactly this pair.
    def google_auth_failed(flow:, error_code:, intent: nil, terms_accepted: nil, user: nil)
      code = normalize_error_code(error_code)

      emit(
        "google_auth_failed",
        level: :warn,
        user: user,
        result: "failure",
        error_code: code,
        properties: {
          auth_flow: normalize_flow(flow),
          auth_provider: "google",
          auth_intent: normalize_intent(intent),
          terms_accepted: boolean_or_nil(terms_accepted),
          error_code: code,
          installation_present: Observability::Context.installation_id.present?
        }
      )
    end

    # ── Android registration ─────────────────────────────────────────────────

    def android_registration_started(source: nil)
      emit(
        "android_registration_started",
        level: :info,
        result: "started",
        properties: { registration_source: source.presence }
      )
    end

    def android_registration_succeeded(user: nil, new_user: nil, installation_linked: nil)
      emit(
        "android_registration_succeeded",
        level: :info,
        user: user,
        result: "success",
        properties: {
          new_user: boolean_or_nil(new_user),
          installation_present: Observability::Context.installation_id.present?,
          installation_linked: boolean_or_nil(installation_linked)
        }
      )
    end

    def android_registration_failed(error_code:)
      code = normalize_error_code(error_code)

      emit(
        "android_registration_failed",
        level: :warn,
        result: "failure",
        error_code: code,
        properties: { error_code: code }
      )
    end

    # ── Installation link ────────────────────────────────────────────────────

    # Log-only, at debug. AppInstallationReconciliation runs on EVERY
    # authenticated request, so persisting a row here would add one INSERT to
    # every single app request — the exact performance problem observability is
    # supposed to detect, not cause. The link rate's honest denominator is the
    # app_installations table itself, which the check queries directly; this
    # event exists purely for step-by-step debugging and is off by default.
    def installation_link_attempted(user: nil)
      log_only(
        "installation_link_attempted",
        level: :debug,
        result: "attempted",
        metadata: { user_present: !user.nil? }
      )
    end

    def installation_link_succeeded(user: nil, result: "linked")
      emit(
        "installation_link_succeeded",
        level: :info,
        user: user,
        result: normalize_link_result(result),
        properties: {
          installation_linked: true,
          link_result: normalize_link_result(result)
        }
      )
    end

    def installation_link_failed(user: nil, result: "error")
      normalized = normalize_link_result(result)

      emit(
        "installation_link_failed",
        level: :warn,
        user: user,
        result: normalized,
        error_code: normalized,
        properties: {
          installation_linked: false,
          link_result: normalized
        }
      )
    end

    # ── Integrations ─────────────────────────────────────────────────────────

    def integration_delivery_succeeded(integration:, attempt: nil, duration_ms: nil)
      emit(
        "integration_delivery_succeeded",
        level: :info,
        result: "success",
        integration_key: integration.to_s,
        attempt: attempt,
        duration_ms: duration_ms,
        properties: { integration: integration.to_s, attempt: attempt }
      )
    end

    def integration_delivery_failed(integration:, error_code:, attempt: nil, duration_ms: nil)
      code = safe_code(error_code)

      emit(
        "integration_delivery_failed",
        level: :warn,
        result: "failure",
        integration_key: integration.to_s,
        error_code: code,
        attempt: attempt,
        duration_ms: duration_ms,
        properties: { integration: integration.to_s, error_code: code, attempt: attempt }
      )
    end

    # ── Jobs ─────────────────────────────────────────────────────────────────
    # Log-only: a row per job run would bloat product_analytics_events for
    # something observability_heartbeats already records with better structure.

    def job_started(job_key:)
      log_only("job_started", level: :info, job_key: job_key, result: "started")
    end

    def job_succeeded(job_key:, duration_ms: nil, metadata: nil)
      log_only("job_succeeded", level: :info, job_key: job_key, result: "success",
                                duration_ms: duration_ms, metadata: metadata)
    end

    def job_failed(job_key:, error_code:, duration_ms: nil)
      log_only("job_failed", level: :error, job_key: job_key, result: "failure",
                             error_code: safe_code(error_code), duration_ms: duration_ms)
    end

    # ── Internals ────────────────────────────────────────────────────────────

    # Both sinks, in order. Neither may raise: an event is a diagnostic, not a
    # business rule.
    def emit(event_name, level:, properties: {}, user: nil, **log_fields)
      safe_properties = properties.compact

      Observability::Logger.emit(
        event_name,
        level: level,
        **log_fields.except(:properties),
        metadata: safe_properties.presence
      )

      Analytics::ServerEvents.record(
        event_name: event_name,
        user: user,
        properties: safe_properties.merge(Observability::Context.to_event_properties)
      )
      nil
    rescue StandardError => e
      Rails.logger.warn("[observability] event #{event_name} failed: #{e.class}")
      nil
    end

    def log_only(event_name, level:, metadata: nil, **log_fields)
      Observability::Logger.emit(event_name, level: level, metadata: metadata, **log_fields)
      nil
    rescue StandardError => e
      Rails.logger.warn("[observability] event #{event_name} failed: #{e.class}")
      nil
    end

    def normalize_flow(flow)
      value = flow.to_s
      AUTH_FLOWS.include?(value) ? value : "unknown"
    end

    def normalize_intent(intent)
      value = intent.to_s
      AUTH_INTENTS.include?(value) ? value : "unknown"
    end

    def normalize_error_code(code)
      value = code.to_s
      AUTH_ERROR_CODES.include?(value) ? value : "internal_error"
    end

    def normalize_link_result(result)
      value = result.to_s
      LINK_RESULTS.include?(value) ? value : "error"
    end

    # For non-auth codes (integrations), where the vocabulary is open-ended but
    # must still be bounded and free of message text.
    def safe_code(code)
      value = code.to_s.strip
      return "unknown" if value.empty?

      value.gsub(/[^A-Za-z0-9_.:-]/, "_")[0, 64]
    end

    def boolean_or_nil(value)
      return nil if value.nil?

      ActiveModel::Type::Boolean.new.cast(value) ? true : false
    end
  end
end
