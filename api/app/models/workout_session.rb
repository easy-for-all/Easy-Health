class WorkoutSession < ApplicationRecord
  belongs_to :user
  belongs_to :workout_day

  validates :completed_at, presence: true
  validates :duration_minutes, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :fatigue_level, numericality: { only_integer: true, in: 1..5 }, allow_nil: true
end
