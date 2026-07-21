class ScheduledWorkoutReminderEventEmitter
  def initialize(result:, occurred_at: Time.current, source: "scheduled_workout_reminder_scheduler")
    @result = result
    @occurred_at = occurred_at
    @source = source
  end

  def call
    RelationshipEventTracker.track(
      user: result.user,
      event_name: ScheduledWorkoutReminderEligibility::EVENT_NAME,
      metadata: event_metadata,
      occurred_at: occurred_at,
      idempotency_key: result.idempotency_key,
      source: source
    )
  end

  private

  attr_reader :result, :occurred_at, :source

  def event_metadata
    schedule = result.schedule
    plan = result.plan
    {
      campaign: result.campaign,
      activation: {
        plan_id: plan.id,
        workout_id: result.workout_id,
        preferred_workout_time: schedule.preferred_workout_time,
        reminder_time: schedule.reminder_time,
        reminder_local_date: schedule.reminder_local_date,
        reminder_number: result.reminder_number,
        maximum_reminders: result.maximum_reminders,
        days_since_workout_created: days_since_workout_created(plan, schedule),
        first_workout_completed: false
      }
    }
  end

  def days_since_workout_created(plan, schedule)
    reminder_date = schedule.reminder_at.in_time_zone(schedule.timezone).to_date
    created_date = plan.created_at.in_time_zone(schedule.timezone).to_date
    [ (reminder_date - created_date).to_i, 0 ].max
  end
end
