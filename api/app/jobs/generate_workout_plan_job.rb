class GenerateWorkoutPlanJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    user = User.find_by(id: user_id)
    return unless user

    WorkoutPlanGeneratorService.new(user).call
  rescue => e
    Rails.logger.error("[GenerateWorkoutPlanJob] Failed for user #{user_id}: #{e.message}")
  end
end
