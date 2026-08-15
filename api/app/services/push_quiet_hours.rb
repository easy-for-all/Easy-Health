# The window in which EasyHealth is willing to deliver a push, in the user's
# own timezone.
#
# This is a DISPATCH concern only. Quiet hours must never stop a business event
# from being created: "the user has been inactive for 3 days" is true at 05:00
# just as it is at 15:00, and suppressing the fact because of the clock loses it
# forever. Event producers therefore do not consult this class; the push
# dispatch path does.
class PushQuietHours
  DEFAULT_START_TIME = "22:00".freeze
  DEFAULT_END_TIME = "07:00".freeze
  START_HOUR = 22
  END_HOUR = 7

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("PUSH_QUIET_HOURS_ENABLED", "false"))
  end

  def self.time_zone_for(user)
    CommunicationTime.zone_for(user)
  end

  def self.allowed?(user:, at: Time.current)
    !quiet?(user:, at:)
  end

  def self.quiet?(user:, at: Time.current)
    local = at.in_time_zone(time_zone_for(user))
    minute = local.hour * 60 + local.min
    start_minute = quiet_start_minutes
    end_minute = quiet_end_minutes

    return false if start_minute == end_minute
    return minute >= start_minute && minute < end_minute if start_minute < end_minute

    minute >= start_minute || minute < end_minute
  end

  # When the window reopens, in the user's timezone. PushDispatch persists this
  # as next_allowed_at so the backend sweep can release the already-decided Make
  # dispatch without asking Make to call again.
  def self.next_allowed_at(user:, at: Time.current)
    zone = time_zone_for(user)
    local = at.in_time_zone(zone)
    return local if allowed?(user: user, at: at)

    end_minute = quiet_end_minutes
    target_date = next_allowed_date(local)
    zone.local(target_date.year, target_date.month, target_date.day, end_minute / 60, end_minute % 60)
  end

  def self.window_label
    "#{format_minutes(quiet_start_minutes)}-#{format_minutes(quiet_end_minutes)}"
  end

  def self.quiet_start_minutes
    configured_minutes("PUSH_QUIET_HOURS_START", DEFAULT_START_TIME)
  end

  def self.quiet_end_minutes
    configured_minutes("PUSH_QUIET_HOURS_END", DEFAULT_END_TIME)
  end

  def self.next_allowed_date(local)
    start_minute = quiet_start_minutes
    end_minute = quiet_end_minutes
    minute = local.hour * 60 + local.min

    if start_minute < end_minute
      local.to_date
    elsif minute >= start_minute
      local.to_date + 1
    else
      local.to_date
    end
  end

  def self.configured_minutes(key, fallback)
    parse_minutes(ENV.fetch(key, fallback)) || parse_minutes(fallback)
  end

  def self.parse_minutes(value)
    match = value.to_s.match(/\A([01]?\d|2[0-3]):([0-5]\d)\z/)
    return nil unless match

    match[1].to_i * 60 + match[2].to_i
  end

  def self.format_minutes(value)
    format("%02d:%02d", value / 60, value % 60)
  end
end
