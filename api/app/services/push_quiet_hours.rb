# Quiet-hours guard for push emission. Engagement pushes are only emitted
# between 08:00 and 21:00 in the user's local time. Outside the window the
# eligibility job simply skips the user; the next cron tick re-evaluates
# (idempotency + live-condition re-check guarantee a single emission).
#
# No per-user scheduling is created — this is intentionally a stateless check.
class PushQuietHours
  START_HOUR = 8   # inclusive (08:00)
  END_HOUR = 21    # inclusive up to 20:59; 21:00 is the cutoff
  DEFAULT_TIME_ZONE = "America/Sao_Paulo".freeze

  def self.allowed?(user:, at: Time.current)
    zone = ActiveSupport::TimeZone[user&.time_zone.presence || DEFAULT_TIME_ZONE] ||
           ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
    hour = at.in_time_zone(zone).hour
    hour >= START_HOUR && hour < END_HOUR
  end
end
