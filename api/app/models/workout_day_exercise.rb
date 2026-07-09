class WorkoutDayExercise < ApplicationRecord
  CARDIO_TYPES = %w[cardio corrida caminhada hiit natacao].freeze
  TIMED_TYPES  = %w[timed].freeze
  INTENSITIES  = %w[leve moderado intenso].freeze

  belongs_to :workout_day
  belongs_to :exercise
  belongs_to :workout_block, optional: true

  validates :sets, presence: true, numericality: { only_integer: true, greater_than: 0 }, unless: -> { cardio? || timed? }
  validates :reps, presence: true, numericality: { only_integer: true, greater_than: 0 }, unless: -> { cardio? || timed? }
  validates :rest_seconds, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, unless: :timed?
  validates :order_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :intensity, inclusion: { in: INTENSITIES }, allow_nil: true
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  # Every WorkoutDayExercise must belong to a block (workout_block_id is
  # NOT NULL). Any creation path that doesn't know about blocks yet (AI
  # generator, manual add, duplicate_day) gets a "single" block for free
  # here, instead of having to be updated individually to build one.
  # Must run before_create (not after_create): the NOT NULL constraint is
  # enforced at INSERT time, before an after_create callback would ever get
  # a chance to backfill the column.
  before_create :ensure_single_block!

  def cardio?
    CARDIO_TYPES.include?(exercise&.exercise_type)
  end

  def timed?
    TIMED_TYPES.include?(exercise&.exercise_type)
  end

  def in_multi_exercise_block?
    workout_block&.multi_exercise? || false
  end

  # Also called directly (not just as a callback) by BlockBackfillService on
  # already-persisted legacy rows, so it has to support both an unsaved
  # record (about to be inserted) and an existing one (needs an update).
  def ensure_single_block!
    return if workout_block_id.present?

    next_position = workout_day.workout_blocks.maximum(:position).to_i + 1
    block = workout_day.workout_blocks.create!(block_type: "single", position: next_position, rounds: 1)

    if persisted?
      update_columns(workout_block_id: block.id, position_in_block: 0)
    else
      self.workout_block = block
      self.position_in_block = 0
    end
  end
end
