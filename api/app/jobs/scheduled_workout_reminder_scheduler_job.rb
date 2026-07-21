class ScheduledWorkoutReminderSchedulerJob < ApplicationJob
  queue_as :default

  SOURCE = "scheduled_workout_reminder_scheduler".freeze

  def perform(now: Time.current, only_user_ids: nil)
    stats = Hash.new(0)

    candidate_users(only_user_ids: only_user_ids).find_each do |user|
      stats[:candidates] += 1
      notify("candidate", user_id: user.id)

      result = ScheduledWorkoutReminderEligibility.new(user:, now: now).call
      unless result.eligible?
        stats[:skipped] += 1
        log("skipped", result.to_h)
        notify("skipped", result.to_h)
        next
      end

      stats[:eligible] += 1
      notify("eligible", result.to_h)
      event = create_event(result, now:)

      if event&.previously_new_record?
        stats[:event_created] += 1
        log("event_created", result.to_h.merge(event_id: event.id, make_delivery_status: event.make_delivery_status))
        notify("event_created", result.to_h.merge(event_id: event.id))

        if event.make_delivery_status == "pending"
          stats[:make_delivery_enqueued] += 1
          notify("make_delivery_enqueued", result.to_h.merge(event_id: event.id))
        end

        PushJourney.track_eligible(
          user: result.user,
          event_name: ScheduledWorkoutReminderEligibility::EVENT_NAME,
          metadata: {
            campaign_key: result.campaign,
            source_event_id: event.id,
            reminder_number: result.reminder_number
          }
        )
      elsif event
        stats[:duplicate_prevented] += 1
        log("duplicate_prevented", result.to_h.merge(event_id: event.id))
        notify("duplicate_prevented", result.to_h.merge(event_id: event.id))
      end
    end

    Rails.logger.info("[ScheduledWorkoutReminderSchedulerJob] #{stats.inspect}")
    stats
  end

  private

  def candidate_users(only_user_ids:)
    relation = User
      .joins(:health_profile, :notification_preferences, :workout_plans, :device_tokens)
      .where(deletion_requested_at: nil, anonymized_at: nil)
      .where(workout_plans: { active: true })
      .where(user_notification_preferences: { push_enabled: true, workout_reminders_enabled: true })
      .where(device_tokens: { enabled: true, invalidated_at: nil, permission_status: "granted" })
      .where.not(users: { time_zone: [ nil, "" ] })
      .where.not(health_profiles: { preferred_workout_time: nil })
      .where.not(health_profiles: { preferred_workout_period: "variable" })
      .select("users.*")
      .distinct

    ids = Array(only_user_ids).compact.map(&:to_i).select(&:positive?)
    ids.any? ? relation.where(users: { id: ids }) : relation
  end

  def create_event(result, now:)
    ScheduledWorkoutReminderEventEmitter.new(result:, occurred_at: now, source: SOURCE).call
  end

  def notify(name, payload)
    ActiveSupport::Notifications.instrument("scheduled_workout_reminder.#{name}", payload)
  end

  def log(action, payload)
    Rails.logger.info("[ScheduledWorkoutReminder] #{payload.merge(action: action).to_json}")
  end
end
