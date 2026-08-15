class ScheduledWorkoutReminderEligibility
  EVENT_NAME = "scheduled_workout_reminder_due".freeze
  CAMPAIGN = "first_workout_scheduled_reminder_v1".freeze
  MANUAL_CAMPAIGN = "first_workout_scheduled_reminder_manual_test".freeze
  MAXIMUM_REMINDERS = 3

  Result = Struct.new(
    :eligible,
    :reason,
    :user,
    :plan,
    :workout_id,
    :schedule,
    :reminder_number,
    :maximum_reminders,
    :idempotency_key,
    :campaign,
    keyword_init: true
  ) do
    def eligible?
      eligible
    end

    def to_h
      {
        eligible: eligible,
        reason: reason,
        user_id: user&.id,
        plan_id: plan&.id,
        workout_id: workout_id,
        reminder_number: reminder_number,
        maximum_reminders: maximum_reminders,
        idempotency_key: idempotency_key,
        campaign: campaign,
        timezone: schedule&.timezone,
        preferred_workout_time: schedule&.preferred_workout_time,
        reminder_time: schedule&.reminder_time,
        reminder_local_date: schedule&.reminder_local_date
      }.compact
    end
  end

  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("SCHEDULED_WORKOUT_REMINDER_ENABLED", "false"))
  end

  def initialize(user:, now: Time.current, window: ScheduledWorkoutReminderSchedule::DEFAULT_WINDOW,
                 campaign: CAMPAIGN, manual: false)
    @user = user
    @now = now
    @window = window
    @campaign = campaign
    @manual = manual
  end

  # Only BUSINESS rules may stop the event from being born.
  #
  # Everything about whether a push can actually be delivered — push_enabled,
  # workout_reminders_enabled, an active device token, the Make webhook being
  # configured, quiet hours — was checked here before, which meant "this user
  # asked to train at 07:00 and it is 06:30" stopped being recorded because of a
  # setting that could change by the time Make asked. Those are dispatch
  # concerns now (Make::PushDispatchRequest), where they are re-evaluated at the
  # moment they matter.
  def call
    return ineligible("feature_disabled") unless manual? || self.class.enabled?
    return ineligible("missing_user") unless user
    return ineligible("user_deleted_or_anonymized") unless MakeWebhookEligibility.account_valid?(user)

    plan = user.active_workout_plan
    return ineligible("missing_plan") unless plan

    profile = user.health_profile
    return ineligible("missing_profile") unless profile
    return ineligible("variable_schedule") if profile.preferred_workout_period == "variable"
    return ineligible("missing_preferred_workout_time") if profile.preferred_workout_time.blank?

    return ineligible("workout_completed") if workout_completed_for_plan?(plan)

    schedule = schedule_for
    return ineligible("outside_window") unless schedule
    if !manual? && plan.created_at && schedule.reminder_at.utc < plan.created_at
      return ineligible("plan_created_after_reminder", plan:, schedule:)
    end

    sent_count = reminder_events_for(plan).count
    return ineligible("maximum_reached", plan:, schedule:) if sent_count >= MAXIMUM_REMINDERS
    return ineligible("already_sent_today", plan:, schedule:) if sent_for_local_date?(plan, schedule.reminder_local_date)

    reminder_number = sent_count + 1
    eligible(plan:, schedule:, reminder_number:)
  rescue ArgumentError
    ineligible("invalid_schedule")
  end

  private

  attr_reader :user, :now, :window, :campaign

  def manual?
    @manual
  end

  def schedule_for
    if manual?
      ScheduledWorkoutReminderSchedule.next_occurrence(user:, now:)
    else
      ScheduledWorkoutReminderSchedule.due(user:, now:, window:)
    end
  end

  def workout_completed_for_plan?(plan)
    completed = user.workout_sessions.where(status: "completed", completion_status: "completed")
    return true if completed.joins(:workout_day).where(workout_days: { workout_plan_id: plan.id }).exists?

    completed.where(workout_day_id: nil).where("completed_at >= ?", plan.created_at).exists?
  end

  def reminder_events_for(plan)
    user.user_events
        .where(event_name: EVENT_NAME)
        .where("metadata ->> 'campaign' = ?", campaign)
        .where("metadata #>> '{activation,plan_id}' = ?", plan.id.to_s)
  end

  def sent_for_local_date?(plan, local_date)
    reminder_events_for(plan)
      .where("metadata #>> '{activation,reminder_local_date}' = ?", local_date.to_s)
      .exists?
  end

  def workout_id_for(plan)
    plan.workout_days
        .order(Arel.sql("COALESCE(position, day_of_week) ASC"))
        .limit(1)
        .pick(:id)
  end

  def idempotency_key_for(plan, schedule)
    if campaign != CAMPAIGN
      return "scheduled-workout-reminder-manual-test:v1:user:#{user.id}:plan:#{plan.id}:at:#{now.to_i}"
    end

    "scheduled-workout-reminder:v1:user:#{user.id}:plan:#{plan.id}:date:#{schedule.reminder_local_date}"
  end

  def eligible(plan:, schedule:, reminder_number:)
    Result.new(
      eligible: true,
      reason: "eligible",
      user: user,
      plan: plan,
      workout_id: workout_id_for(plan),
      schedule: schedule,
      reminder_number: reminder_number,
      maximum_reminders: MAXIMUM_REMINDERS,
      idempotency_key: idempotency_key_for(plan, schedule),
      campaign: campaign
    )
  end

  def ineligible(reason, plan: nil, schedule: nil)
    Result.new(
      eligible: false,
      reason: reason,
      user: user,
      plan: plan,
      workout_id: plan && workout_id_for(plan),
      schedule: schedule,
      maximum_reminders: MAXIMUM_REMINDERS,
      campaign: campaign
    )
  end
end
