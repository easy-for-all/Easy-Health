# The window in which EasyHealth is willing to deliver a push, in the user's
# own timezone.
#
# This is a DISPATCH concern only. Quiet hours must never stop a business event
# from being created: "the user has been inactive for 3 days" is true at 05:00
# just as it is at 15:00, and suppressing the fact because of the clock loses it
# forever. Event producers therefore do not consult this class; the push
# dispatch path does.
class PushQuietHours
  START_HOUR = 8
  END_HOUR = 21
  DEFAULT_TIME_ZONE = "America/Sao_Paulo".freeze

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("PUSH_QUIET_HOURS_ENABLED", "false"))
  end

  def self.time_zone_for(user)
    ActiveSupport::TimeZone[user&.time_zone.presence || DEFAULT_TIME_ZONE] ||
      ActiveSupport::TimeZone[DEFAULT_TIME_ZONE]
  end

  def self.allowed?(user:, at: Time.current)
    hour = at.in_time_zone(time_zone_for(user)).hour
    hour >= START_HOUR && hour < END_HOUR
  end

  # When the window reopens, in the user's timezone. Returned to Make on a
  # quiet-hours skip so the orchestrator can reschedule instead of silently
  # dropping the communication — the backend deliberately does no retry of its
  # own here.
  def self.next_allowed_at(user:, at: Time.current)
    zone = time_zone_for(user)
    local = at.in_time_zone(zone)
    return local if allowed?(user: user, at: at)

    target_date = local.hour >= END_HOUR ? local.to_date + 1 : local.to_date
    zone.local(target_date.year, target_date.month, target_date.day, START_HOUR, 0)
  end
end
