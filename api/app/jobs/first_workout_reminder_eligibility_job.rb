# Schedules the first activation push at the user's next preferred local time.
# Candidates: created a plan recently (activation_workout_created) and are still
# eligible (no workout session yet, opted in, has a preferred time, etc.).
class FirstWorkoutReminderEligibilityJob < ActivationPushSchedulerJob
  CANDIDATE_WINDOW = 3.days

  private

  def notification_type
    "first_workout_reminder"
  end

  def candidate_user_ids
    UserEvent
      .where(event_name: "activation_workout_created", created_at: CANDIDATE_WINDOW.ago..)
      .distinct
      .pluck(:user_id)
  end

  def scheduled_time_for(user)
    PreferredWorkoutSchedule.next_occurrence(user)
  end
end
