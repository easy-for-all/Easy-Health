class ExerciseSet < ApplicationRecord
  belongs_to :exercise_session

  validates :set_number, presence: true, numericality: { only_integer: true, greater_than: 0 },
    uniqueness: { scope: :exercise_session_id }
  validates :completed_at, presence: true
  validates :weight_kg, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :reps, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
end
