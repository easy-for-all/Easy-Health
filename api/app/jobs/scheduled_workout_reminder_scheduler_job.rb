class ScheduledWorkoutReminderSchedulerJob < ApplicationJob
  # Runs every ~15min from cron. Silence means nobody gets the reminder they
  # asked for at onboarding, with no other symptom.
  def self.observability_heartbeat_key = "scheduled_workout_reminder"

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
        stats[:suppressed] += 1 if result.reason == ScheduledWorkoutReminderSuppression::REASON
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

    @heartbeat_metadata = stats.to_h
    Rails.logger.info("[ScheduledWorkoutReminderSchedulerJob] #{stats.inspect}")
    stats
  end

  attr_reader :heartbeat_metadata

  private

  # Business preconditions only. Push preferences and device tokens are NOT
  # joined here any more: whether the reminder can be delivered is answered at
  # dispatch, and filtering on it here silently erased the event for anyone who
  # had not granted push yet — exactly the users a reminder is meant to reach.
  def candidate_users(only_user_ids:)
    relation = User
      .joins(:health_profile, :workout_plans)
      .where(deletion_requested_at: nil, anonymized_at: nil)
      .where(workout_plans: { active: true })
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
