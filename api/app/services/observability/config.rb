module Observability
  # Single place where every observability ENV var is read and defaulted.
  #
  # Nothing else in Observability:: should call ENV directly: the admin panel
  # renders `Config.to_h` as the "thresholds" block so the operator can see the
  # exact ruler a check is judging by, and that only works if there is one ruler.
  #
  # Values are read on every call (no memoization) so specs can flip them with
  # the existing `with_env` helper without a reset hook.
  module Config
    module_function

    # ── Master switches ──────────────────────────────────────────────────────

    def enabled?
      flag("OBSERVABILITY_ENABLED", default: true)
    end

    def alerts_enabled?
      flag("OBSERVABILITY_ALERTS_ENABLED", default: false)
    end

    def json_logs?
      return true if Rails.env.production?
      flag("OBSERVABILITY_JSON_LOGS", default: false)
    end

    # ── Alerting ─────────────────────────────────────────────────────────────

    def alert_webhook_url
      ENV["OBSERVABILITY_ALERT_WEBHOOK_URL"].presence
    end

    def alert_webhook_token
      ENV["OBSERVABILITY_ALERT_WEBHOOK_TOKEN"].presence
    end

    def alert_cooldown_minutes
      integer("OBSERVABILITY_ALERT_COOLDOWN_MINUTES", default: 60, min: 0)
    end

    def alert_webhook_timeout_seconds
      integer("OBSERVABILITY_ALERT_WEBHOOK_TIMEOUT_SECONDS", default: 5, min: 1)
    end

    # ── Retention ────────────────────────────────────────────────────────────

    def check_retention_days
      integer("OBSERVABILITY_CHECK_RETENTION_DAYS", default: 90, min: 1)
    end

    # ── Sample floors ────────────────────────────────────────────────────────

    def min_android_sample
      integer("OBSERVABILITY_MIN_ANDROID_SAMPLE", default: 10, min: 1)
    end

    def min_google_auth_sample
      integer("OBSERVABILITY_MIN_GOOGLE_AUTH_SAMPLE", default: 10, min: 1)
    end

    def min_http_sample
      integer("OBSERVABILITY_MIN_HTTP_SAMPLE", default: 20, min: 1)
    end

    # ── Android registration conversion ──────────────────────────────────────

    def android_registration_warning_rate
      rate("ANDROID_REGISTRATION_WARNING_RATE", default: 0.30)
    end

    def android_registration_critical_rate
      rate("ANDROID_REGISTRATION_CRITICAL_RATE", default: 0.15)
    end

    def android_registration_warning_drop
      rate("ANDROID_REGISTRATION_WARNING_DROP", default: 0.40)
    end

    def android_registration_critical_drop
      rate("ANDROID_REGISTRATION_CRITICAL_DROP", default: 0.60)
    end

    # ── Android installation link ────────────────────────────────────────────

    def android_link_warning_rate
      rate("ANDROID_LINK_WARNING_RATE", default: 0.50)
    end

    def android_link_critical_rate
      rate("ANDROID_LINK_CRITICAL_RATE", default: 0.30)
    end

    # Grace between a successful authentication and the row being linked.
    # AppInstallationReconciliation writes user_id and last_authenticated_at in
    # the same update_columns call, so anything older than this is a real bug,
    # not a race.
    def link_tolerance_seconds
      integer("OBSERVABILITY_LINK_TOLERANCE_SECONDS", default: 300, min: 30)
    end

    # ── Google auth ──────────────────────────────────────────────────────────

    def google_auth_warning_error_rate
      rate("GOOGLE_AUTH_WARNING_ERROR_RATE", default: 0.10)
    end

    def google_auth_critical_error_rate
      rate("GOOGLE_AUTH_CRITICAL_ERROR_RATE", default: 0.25)
    end

    def google_auth_window_minutes
      integer("GOOGLE_AUTH_WINDOW_MINUTES", default: 30, min: 5)
    end

    # ── Jobs & integrations ──────────────────────────────────────────────────

    def heartbeat_warning_multiplier
      rate("OBSERVABILITY_HEARTBEAT_WARNING_MULTIPLIER", default: 1.5, max: 100.0)
    end

    def heartbeat_critical_multiplier
      rate("OBSERVABILITY_HEARTBEAT_CRITICAL_MULTIPLIER", default: 2.0, max: 100.0)
    end

    def job_failure_warning_streak
      integer("OBSERVABILITY_JOB_FAILURE_WARNING_STREAK", default: 3, min: 1)
    end

    def job_failure_critical_streak
      integer("OBSERVABILITY_JOB_FAILURE_CRITICAL_STREAK", default: 5, min: 1)
    end

    def make_backlog_warning
      integer("OBSERVABILITY_MAKE_BACKLOG_WARNING", default: 10, min: 1)
    end

    def make_backlog_critical
      integer("OBSERVABILITY_MAKE_BACKLOG_CRITICAL", default: 50, min: 1)
    end

    # A pending Make delivery is only "stuck" once it is older than this. The
    # ActiveJob adapter is :async, so every deploy legitimately drops in-flight
    # retries — without this floor the check would fire on every deploy.
    def make_backlog_age_minutes
      integer("OBSERVABILITY_MAKE_BACKLOG_AGE_MINUTES", default: 30, min: 1)
    end

    def stripe_failure_warning
      integer("OBSERVABILITY_STRIPE_FAILURE_WARNING", default: 1, min: 1)
    end

    def stripe_failure_critical
      integer("OBSERVABILITY_STRIPE_FAILURE_CRITICAL", default: 5, min: 1)
    end

    # ── HTTP (in-process aggregate, feeds card 1) ────────────────────────────

    def http_error_warning_rate
      rate("OBSERVABILITY_HTTP_ERROR_WARNING_RATE", default: 0.05)
    end

    def http_error_critical_rate
      rate("OBSERVABILITY_HTTP_ERROR_CRITICAL_RATE", default: 0.15)
    end

    def http_latency_warning_seconds
      rate("OBSERVABILITY_HTTP_LATENCY_WARNING_SECONDS", default: 2.0, max: 600.0)
    end

    def http_latency_critical_seconds
      rate("OBSERVABILITY_HTTP_LATENCY_CRITICAL_SECONDS", default: 5.0, max: 600.0)
    end

    # ── BI replica ───────────────────────────────────────────────────────────

    # The installed crontab lives on the VPS and is NOT knowable from this repo:
    # scripts/bi_replica/install_cron.sh only supplies a default of "0 2 * * *"
    # via CRON_SCHEDULE. Rather than hardcode an hour that may not match, the
    # staleness check is driven by these two values — keep them consistent with
    # whatever `crontab -l` actually shows.
    def bi_replica_expected_hour
      integer("BI_REPLICA_EXPECTED_HOUR", default: 3, min: 0, max: 23)
    end

    def bi_replica_grace_minutes
      integer("BI_REPLICA_GRACE_MINUTES", default: 90, min: 0)
    end

    # ── Android analytics ingestion ──────────────────────────────────────────

    def analytics_ingestion_window_hours
      integer("OBSERVABILITY_ANALYTICS_WINDOW_HOURS", default: 2, min: 1)
    end

    # Below this trailing baseline the app simply does not produce enough
    # traffic for "no events" to mean anything — report insufficient_data
    # instead of inventing an incident.
    def analytics_ingestion_traffic_floor
      rate("OBSERVABILITY_ANALYTICS_TRAFFIC_FLOOR", default: 5.0, max: 100_000.0)
    end

    # Optional descriptive release cohort floor. This is intentionally not a
    # reconciliation eligibility threshold: the web bundle can change without a
    # native build bump.
    def current_build_min
      optional_integer("OBSERVABILITY_CURRENT_BUILD_MIN", min: 0)
    end

    # ── Identifier hashing ───────────────────────────────────────────────────

    def hash_salt
      ENV["OBSERVABILITY_HASH_SALT"].presence ||
        Rails.application.secret_key_base
    end

    # ── Admin dashboard ──────────────────────────────────────────────────────

    def dashboard_cache_seconds
      integer("OBSERVABILITY_DASHBOARD_CACHE_SECONDS", default: 45, min: 0)
    end

    # Rendered in the admin payload so the panel always shows the rule it is
    # being judged by. Only tunables — never secrets (webhook URL/token are
    # deliberately absent).
    def to_h
      {
        enabled: enabled?,
        alerts_enabled: alerts_enabled?,
        alert_cooldown_minutes: alert_cooldown_minutes,
        check_retention_days: check_retention_days,
        min_android_sample: min_android_sample,
        min_google_auth_sample: min_google_auth_sample,
        min_http_sample: min_http_sample,
        android_registration_warning_rate: android_registration_warning_rate,
        android_registration_critical_rate: android_registration_critical_rate,
        android_registration_warning_drop: android_registration_warning_drop,
        android_registration_critical_drop: android_registration_critical_drop,
        android_link_warning_rate: android_link_warning_rate,
        android_link_critical_rate: android_link_critical_rate,
        link_tolerance_seconds: link_tolerance_seconds,
        google_auth_warning_error_rate: google_auth_warning_error_rate,
        google_auth_critical_error_rate: google_auth_critical_error_rate,
        google_auth_window_minutes: google_auth_window_minutes,
        heartbeat_warning_multiplier: heartbeat_warning_multiplier,
        heartbeat_critical_multiplier: heartbeat_critical_multiplier,
        job_failure_warning_streak: job_failure_warning_streak,
        job_failure_critical_streak: job_failure_critical_streak,
        make_backlog_warning: make_backlog_warning,
        make_backlog_critical: make_backlog_critical,
        make_backlog_age_minutes: make_backlog_age_minutes,
        stripe_failure_warning: stripe_failure_warning,
        stripe_failure_critical: stripe_failure_critical,
        http_error_warning_rate: http_error_warning_rate,
        http_error_critical_rate: http_error_critical_rate,
        http_latency_warning_seconds: http_latency_warning_seconds,
        http_latency_critical_seconds: http_latency_critical_seconds,
        bi_replica_expected_hour: bi_replica_expected_hour,
        bi_replica_grace_minutes: bi_replica_grace_minutes,
        analytics_ingestion_window_hours: analytics_ingestion_window_hours,
        analytics_ingestion_traffic_floor: analytics_ingestion_traffic_floor,
        current_build_min: current_build_min
      }
    end

    # ── Coercion helpers ─────────────────────────────────────────────────────

    def flag(name, default:)
      raw = ENV[name]
      return default if raw.blank?

      %w[1 true yes on].include?(raw.to_s.strip.downcase)
    end

    def integer(name, default:, min: nil, max: nil)
      raw = ENV[name]
      value = raw.presence ? Integer(raw, exception: false) : nil
      value = default if value.nil?
      value = min if min && value < min
      value = max if max && value > max
      value
    end

    def optional_integer(name, min: nil, max: nil)
      value = Integer(ENV[name], exception: false)
      return nil if value.nil?

      value = min if min && value < min
      value = max if max && value > max
      value
    end

    # Ratios and durations share the same coercion: a malformed value falls back
    # to the default rather than silently becoming 0.0 and firing every check.
    def rate(name, default:, min: 0.0, max: 1.0)
      raw = ENV[name]
      value = raw.presence ? Float(raw, exception: false) : nil
      value = default if value.nil?
      value = min if value < min
      value = max if value > max
      value
    end
  end
end
