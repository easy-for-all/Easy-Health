# Turns "I like to train at 07:00" into the instant a reminder becomes DUE.
#
#   reminder_due_at = preferred_workout_time - lead_time, in the user's timezone
#
# DEFAULT_WINDOW is the scheduler's TOLERANCE, not part of the product rule. The
# detection is `due_at <= now AND due_at > now - window`, so a reminder is never
# sent early: a 07:10 workout is due at 06:40, a 06:30 tick emits nothing and the
# 06:45 tick emits it 5 minutes late. The window only has to be at least as long
# as the cron interval, or a due moment falls between two ticks and is lost.
class ScheduledWorkoutReminderSchedule
  DEFAULT_LEAD_MINUTES = 30
  # Cron runs every ~15min; 20 gives it margin without widening the lateness a
  # user can actually experience (idempotency still caps it at one per day).
  DEFAULT_WINDOW = 20.minutes

  Result = Struct.new(
    :reminder_at,
    :workout_at,
    :timezone,
    :preferred_workout_time,
    :reminder_time,
    :reminder_local_date,
    :reminder_lead_minutes,
    keyword_init: true
  ) do
    # Explicit alias: reminder_at IS the due moment, and naming it that way
    # keeps "when it became due" separate from "when we noticed".
    def reminder_due_at
      reminder_at
    end
  end

  # Central so the lead time can be tuned (15/30/45) without touching the jobs,
  # services or payload builders that reference it.
  def self.lead_time
    ENV.fetch("SCHEDULED_WORKOUT_REMINDER_LEAD_MINUTES", DEFAULT_LEAD_MINUTES.to_s)
       .to_i.clamp(5, 180).minutes
  end

  def self.lead_minutes
    (lead_time / 60).to_i
  end

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
      reminder_at = workout_at - lead_time

      Result.new(
        reminder_at: reminder_at,
        workout_at: workout_at,
        timezone: zone.tzinfo.name,
        preferred_workout_time: format_time(workout_at),
        reminder_time: format_time(reminder_at),
        reminder_local_date: reminder_at.to_date.iso8601,
        reminder_lead_minutes: lead_minutes
      )
    end

    def format_time(time)
      time.strftime("%H:%M")
    end
  end
end
