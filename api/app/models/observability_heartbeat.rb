# Liveness record for one recurring process (job, cron, integration, pipeline).
#
# This table exists because most recurring work in this app runs OUTSIDE the
# Puma process — rake tasks under VPS cron, and an ActiveJob :async adapter that
# loses queued work on restart. Anything held in the web process's memory is
# blind to all of it. A row here is the only durable evidence that a scheduled
# process actually ran.
#
# Writes go through Observability::Heartbeat, which never raises. Read state via
# #status / #stale?.
class ObservabilityHeartbeat < ApplicationRecord
  CATEGORIES = %w[job cron integration pipeline].freeze

  STATUS_HEALTHY  = "healthy".freeze
  STATUS_WARNING  = "warning".freeze
  STATUS_CRITICAL = "critical".freeze
  # Registered but never yet succeeded, and still inside its first expected
  # interval. Alerting here would fire on every fresh deploy.
  STATUS_PENDING  = "insufficient_data".freeze

  validates :key, presence: true, uniqueness: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :expected_interval_seconds, numericality: { greater_than: 0 }

  scope :by_key, ->(key) { where(key: key.to_s) }

  def seconds_since_success(now: Time.current)
    return nil if last_succeeded_at.nil?

    (now - last_succeeded_at).to_i
  end

  def stale?(now: Time.current)
    status(now: now).in?([ STATUS_WARNING, STATUS_CRITICAL ])
  end

  def status(now: Time.current)
    elapsed = seconds_since_success(now: now)

    if elapsed.nil?
      # Never succeeded. Give it one full interval from registration before
      # calling it broken — otherwise a heartbeat added by a deploy is critical
      # the moment it is created.
      age = (now - (created_at || now)).to_i
      return age > expected_interval_seconds ? STATUS_CRITICAL : STATUS_PENDING
    end

    return STATUS_CRITICAL if elapsed > expected_interval_seconds * Observability::Config.heartbeat_critical_multiplier
    return STATUS_WARNING if elapsed > expected_interval_seconds * Observability::Config.heartbeat_warning_multiplier

    STATUS_HEALTHY
  end

  def as_observability_json(now: Time.current)
    {
      key: key,
      category: category,
      status: status(now: now),
      expected_interval_seconds: expected_interval_seconds,
      last_started_at: last_started_at,
      last_succeeded_at: last_succeeded_at,
      last_failed_at: last_failed_at,
      last_duration_ms: last_duration_ms,
      seconds_since_success: seconds_since_success(now: now),
      consecutive_failures: consecutive_failures,
      last_error_code: last_error_code
    }
  end
end
