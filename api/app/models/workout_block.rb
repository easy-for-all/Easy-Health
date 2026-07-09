class WorkoutBlock < ApplicationRecord
  BLOCK_TYPES = %w[
    single superset bi_set tri_set circuit
    warmup strength_block hypertrophy_block cardio_block
    mobility_block finisher cooldown
  ].freeze

  MULTI_EXERCISE_TYPES = %w[superset bi_set tri_set circuit].freeze

  belongs_to :workout_day
  has_many :workout_day_exercises, -> { order(:position_in_block) }, dependent: :nullify

  validates :block_type, inclusion: { in: BLOCK_TYPES }
  validates :position, presence: true
  validates :rounds, presence: true, numericality: { only_integer: true, greater_than: 0 }

  def multi_exercise?
    MULTI_EXERCISE_TYPES.include?(block_type)
  end
end
