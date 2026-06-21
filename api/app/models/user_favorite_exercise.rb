class UserFavoriteExercise < ApplicationRecord
  belongs_to :user
  belongs_to :exercise

  validates :exercise_id, uniqueness: { scope: :user_id }

  after_commit :trigger_fitness_recalibration, on: [:create, :destroy]

  private

  def trigger_fitness_recalibration
    RecalibrateFitnessProfileJob.perform_later(user_id, source: "exercise_favorited")
  end
end
