class WorkoutDayExercise < ApplicationRecord
  CARDIO_TYPES = %w[cardio corrida caminhada hiit natacao].freeze
  INTENSITIES  = %w[leve moderado intenso].freeze

  belongs_to :workout_day
  belongs_to :exercise

  validates :sets, presence: true, numericality: { only_integer: true, greater_than: 0 }, unless: :cardio?
  validates :reps, presence: true, numericality: { only_integer: true, greater_than: 0 }, unless: :cardio?
  validates :rest_seconds, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :order_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :intensity, inclusion: { in: INTENSITIES }, allow_nil: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  def cardio?
    CARDIO_TYPES.include?(exercise&.exercise_type)
  end
end
