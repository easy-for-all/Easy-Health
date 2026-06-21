class RecalibrateFitnessProfileJob < ApplicationJob
  queue_as :default

  def perform(user_id, source: "event_trigger")
    user = User.find_by(id: user_id)
    return unless user

    FitnessIntelligence.recalculate_safely(user: user, source: source)
    CoachEngine::ContinuousCoach.new(user: user).call
  rescue => e
    Rails.logger.error("[RecalibrateFitnessProfileJob] Failed for user #{user_id}: #{e.message}")
  end
end
