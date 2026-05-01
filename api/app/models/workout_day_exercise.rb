class WorkoutDayExercise < ApplicationRecord
  belongs_to :workout_day
  belongs_to :exercise

  validates :sets, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :reps, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :rest_seconds, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :order_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
