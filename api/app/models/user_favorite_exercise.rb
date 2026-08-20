class UserFavoriteExercise < ApplicationRecord
  belongs_to :user
  belongs_to :exercise

  validates :exercise_id, uniqueness: { scope: :user_id }

  after_commit :trigger_fitness_recalibration_after_create, on: :create
  after_commit :trigger_fitness_recalibration_after_destroy, on: :destroy

  private

  def trigger_fitness_recalibration_after_create
    RecalibrateFitnessProfileJob.perform_later(user_id, source: "favorite_exercise_added")
  end

  def trigger_fitness_recalibration_after_destroy
    RecalibrateFitnessProfileJob.perform_later(user_id, source: "favorite_exercise_removed")
  end
end
