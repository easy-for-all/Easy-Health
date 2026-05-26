class UserFavoriteExercise < ApplicationRecord
  belongs_to :user
  belongs_to :exercise

  validates :exercise_id, uniqueness: { scope: :user_id }
end
