class ScheduledWorkoutReminderSchedule
  LEAD_TIME = 30.minutes
  DEFAULT_WINDOW = 10.minutes

  Result = Struct.new(
    :reminder_at,
    :workout_at,
    :timezone,
    :preferred_workout_time,
    :reminder_time,
    :reminder_local_date,
    keyword_init: true
  )

  class << self
    def due(user:, now: Time.current, window: DEFAULT_WINDOW)
      time = user.health_profile&.preferred_workout_time
      zone = time_zone_for(user)
      return nil if time.blank? || zone.nil?

      local_now = now.in_time_zone(zone)
      target_dates(local_now.to_date).filter_map do |target_date|
        build_result(time:, zone:, target_date:)
      end.find do |result|
        result.reminder_at <= local_now && result.reminder_at > local_now - window
      end
    end

    def next_occurrence(user:, now: Time.current)
      time = user.health_profile&.preferred_workout_time
      zone = time_zone_for(user)
      return nil if time.blank? || zone.nil?

      local_now = now.in_time_zone(zone)
      target_dates(local_now.to_date).filter_map do |target_date|
        build_result(time:, zone:, target_date:)
      end.find { |result| result.reminder_at >= local_now } ||
        build_result(time:, zone:, target_date: local_now.to_date + 2)
    end

    def time_zone_for(user)
      ActiveSupport::TimeZone[user.time_zone.to_s]
    end

    private

    def target_dates(local_date)
      [ local_date, local_date + 1 ]
    end

    def build_result(time:, zone:, target_date:)
      workout_at = zone.local(target_date.year, target_date.month, target_date.day, time.hour, time.min)
      reminder_at = workout_at - LEAD_TIME

      Result.new(
        reminder_at: reminder_at,
        workout_at: workout_at,
        timezone: zone.tzinfo.name,
        preferred_workout_time: format_time(workout_at),
        reminder_time: format_time(reminder_at),
        reminder_local_date: reminder_at.to_date.iso8601
      )
    end

    def format_time(time)
      time.strftime("%H:%M")
    end
  end
end
