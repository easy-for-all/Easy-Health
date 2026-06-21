class InactivityCheckJob < ApplicationJob
  queue_as :default

  INACTIVITY_DAYS = 7

  def perform
    inactive_user_ids = User
      .joins(:workout_sessions)
      .where(workout_sessions: { completed_at: INACTIVITY_DAYS.days.ago.. })
      .distinct
      .pluck(:id)

    User.where.not(id: inactive_user_ids)
        .where(created_at: ..INACTIVITY_DAYS.days.ago)
        .find_each do |user|
      RecalibrateFitnessProfileJob.perform_later(user.id, source: "inactivity_check")
    end
  end
end
