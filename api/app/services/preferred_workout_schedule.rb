# Computes the next local datetime at which to fire an activation push, based on
# the user's declared preferred_workout_time and IANA time zone.
#
# Never fires "right now just because the hour already passed": if today's slot
# is in the past (or within MIN_LEAD), it schedules the next day.
module PreferredWorkoutSchedule
  DEFAULT_TZ = "America/Sao_Paulo".freeze
  MIN_LEAD = 60.minutes

  module_function

  def time_zone_for(user)
    ActiveSupport::TimeZone[user.time_zone.to_s] || ActiveSupport::TimeZone[DEFAULT_TZ]
  end

  # Returns an ActiveSupport::TimeWithZone, or nil if no preferred time is set.
  def next_occurrence(user, after: Time.current, min_lead: MIN_LEAD, not_before: nil)
    time = user.health_profile&.preferred_workout_time
    return nil if time.blank?

    tz = time_zone_for(user)
    floor = [after, not_before].compact.max.in_time_zone(tz)
    candidate = tz.local(floor.year, floor.month, floor.day, time.hour, time.min)
    candidate += 1.day while candidate <= floor + min_lead
    candidate
  end
end
