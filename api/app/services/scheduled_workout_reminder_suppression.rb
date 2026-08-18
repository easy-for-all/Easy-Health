class ScheduledWorkoutReminderSuppression
  SUPPRESSED_EVENT_NAME = "scheduled_workout_reminder_suppressed".freeze
  RESUMED_EVENT_NAME = "scheduled_workout_reminder_resumed".freeze
  REASON = "inactive_5_days".freeze
  RESUME_REASON = "workout_completed_after_inactivity_suppression".freeze
  THRESHOLD_DAYS = 5

  Result = Struct.new(
    :suppressed,
    :transitioned,
    :event,
    :last_completed_workout_at,
    :metadata,
    keyword_init: true
  ) do
    def suppressed?
      suppressed
    end

    def transitioned?
      transitioned
    end
  end

  def initialize(user:, health_profile:, now: Time.current)
    @user = user
    @health_profile = health_profile
    @now = now
  end

  def suppress_if_needed!(schedule:)
    health_profile.with_lock do
      health_profile.reload
      last_completed = last_completed_workout_at

      if health_profile.scheduled_workout_reminder_suppressed_at.present?
        result(suppressed: true, last_completed_workout_at: last_completed)
      elsif !inactive?(last_completed)
        result(suppressed: false, last_completed_workout_at: last_completed)
      else
        detected_at = now
        metadata = suppression_metadata(
          schedule: schedule,
          last_completed_workout_at: last_completed,
          detected_at: detected_at
        )

        persist_suppression!(metadata: metadata, detected_at: detected_at)
        event = track_suppressed!(metadata: metadata, detected_at: detected_at, last_completed_workout_at: last_completed)
        log("suppressed", reason: REASON, last_completed_workout_at: iso8601(last_completed))

        result(
          suppressed: true,
          transitioned: true,
          event: event,
          last_completed_workout_at: last_completed,
          metadata: metadata
        )
      end
    end
  end

  def resume_if_needed!
    health_profile.with_lock do
      health_profile.reload
      suppressed_at = health_profile.scheduled_workout_reminder_suppressed_at
      previous_reason = health_profile.scheduled_workout_reminder_suppression_reason
      last_completed = last_completed_workout_at

      if !(suppressed_at.present? && last_completed.present? && last_completed > suppressed_at)
        result(
          suppressed: suppressed_at.present?,
          last_completed_workout_at: last_completed
        )
      else
        resumed_at = now
        metadata = resume_metadata(
          resumed_at: resumed_at,
          last_completed_workout_at: last_completed,
          previous_suppression_reason: previous_reason
        )

        clear_suppression!
        event = track_resumed!(
          metadata: metadata,
          suppressed_at: suppressed_at,
          last_completed_workout_at: last_completed,
          resumed_at: resumed_at
        )
        log("resumed", reason: RESUME_REASON, last_completed_workout_at: iso8601(last_completed))

        result(
          suppressed: false,
          transitioned: true,
          event: event,
          last_completed_workout_at: last_completed,
          metadata: metadata
        )
      end
    end
  end

  private

  attr_reader :user, :health_profile, :now

  def inactive?(last_completed)
    last_completed.present? && last_completed <= now - THRESHOLD_DAYS.days
  end

  def last_completed_workout_at
    user.workout_sessions.completed_successfully.maximum(:completed_at)
  end

  def suppression_metadata(schedule:, last_completed_workout_at:, detected_at:)
    {
      reason: REASON,
      threshold_days: THRESHOLD_DAYS,
      last_completed_workout_at: iso8601(last_completed_workout_at),
      detected_at: iso8601(detected_at),
      preferred_workout_time: preferred_workout_time(schedule),
      previous_reminder_state: "active",
      new_reminder_state: "suppressed"
    }.compact
  end

  def resume_metadata(resumed_at:, last_completed_workout_at:, previous_suppression_reason:)
    {
      reason: RESUME_REASON,
      resumed_at: iso8601(resumed_at),
      last_completed_workout_at: iso8601(last_completed_workout_at),
      previous_suppression_reason: previous_suppression_reason
    }.compact
  end

  def persist_suppression!(metadata:, detected_at:)
    health_profile.update_columns(
      scheduled_workout_reminder_suppressed_at: detected_at,
      scheduled_workout_reminder_suppression_reason: REASON,
      scheduled_workout_reminder_suppression_metadata: metadata,
      updated_at: Time.current
    )
  end

  def clear_suppression!
    health_profile.update_columns(
      scheduled_workout_reminder_suppressed_at: nil,
      scheduled_workout_reminder_suppression_reason: nil,
      scheduled_workout_reminder_suppression_metadata: {},
      updated_at: Time.current
    )
  end

  def track_suppressed!(metadata:, detected_at:, last_completed_workout_at:)
    UserEventService.track(
      user: user,
      event_name: SUPPRESSED_EVENT_NAME,
      metadata: metadata,
      source: "easyhealth_backend",
      occurred_at: detected_at,
      idempotency_key: [
        "scheduled-workout-reminder-suppressed:v1",
        "user:#{user.id}",
        "last_completed_at:#{idempotency_time(last_completed_workout_at)}"
      ].join(":"),
      suppress_make_delivery: true,
      origin_surface: "backend_scheduler"
    )
  end

  def track_resumed!(metadata:, suppressed_at:, last_completed_workout_at:, resumed_at:)
    UserEventService.track(
      user: user,
      event_name: RESUMED_EVENT_NAME,
      metadata: metadata,
      source: "easyhealth_backend",
      occurred_at: resumed_at,
      idempotency_key: [
        "scheduled-workout-reminder-resumed:v1",
        "user:#{user.id}",
        "suppressed_at:#{idempotency_time(suppressed_at)}",
        "last_completed_at:#{idempotency_time(last_completed_workout_at)}"
      ].join(":"),
      suppress_make_delivery: true,
      origin_surface: "backend_scheduler"
    )
  end

  def result(suppressed:, transitioned: false, event: nil, last_completed_workout_at: nil, metadata: nil)
    Result.new(
      suppressed: suppressed,
      transitioned: transitioned,
      event: event,
      last_completed_workout_at: last_completed_workout_at,
      metadata: metadata
    )
  end

  def preferred_workout_time(schedule)
    schedule&.preferred_workout_time || health_profile.preferred_workout_time&.strftime("%H:%M")
  end

  def iso8601(value)
    value&.iso8601
  end

  def idempotency_time(value)
    value&.utc&.iso8601(6)
  end

  def log(action, payload)
    Rails.logger.info("[ScheduledWorkoutReminder] #{payload.merge(user_id: user.id, action: action).to_json}")
  end
end
