# Schedules the single recovery push ~1 day after the reminder was sent, at the
# next preferred local time. Candidates: users whose reminder was already sent
# and who still haven't engaged.
class FirstWorkoutRecoveryEligibilityJob < ActivationPushSchedulerJob
  CANDIDATE_WINDOW = 7.days

  private

  def notification_type
    "first_workout_recovery"
  end

  def candidate_user_ids
    NotificationDelivery
      .of_type("first_workout_reminder")
      .where(status: %w[sent opened converted], sent_at: CANDIDATE_WINDOW.ago..)
      .distinct
      .pluck(:user_id)
  end

  def scheduled_time_for(user)
    reminder_at = user.notification_preferences&.activation_reminder_sent_at
    return nil if reminder_at.nil?

    PreferredWorkoutSchedule.next_occurrence(
      user,
      not_before: reminder_at + PushActivationEligibility::RECOVERY_MIN_GAP
    )
  end
end
