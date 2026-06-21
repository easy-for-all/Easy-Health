class WorkoutPlan < ApplicationRecord
  belongs_to :user
  has_many :workout_days, dependent: :destroy
  has_one :ai_training_decision_log, dependent: :destroy
  has_one :workout_strategy, dependent: :destroy

  scope :active, -> { where(active: true) }
end
