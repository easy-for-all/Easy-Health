class ExerciseSession < ApplicationRecord
  STATUSES = %w[in_progress completed skipped].freeze
  KINDS = %w[strength cardio timed].freeze

  belongs_to :workout_session
  belongs_to :workout_day_exercise, optional: true
  belongs_to :exercise
  belongs_to :workout_block, optional: true
  has_many :exercise_sets, -> { order(:set_number) }, dependent: :destroy

  validates :order_index, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :exercise_kind, inclusion: { in: KINDS }
  validates :started_at, presence: true

  def strength?
    exercise_kind == "strength"
  end

  def cardio?
    exercise_kind == "cardio"
  end

  def timed?
    exercise_kind == "timed"
  end
end
