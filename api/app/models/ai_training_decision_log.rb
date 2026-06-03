class AiTrainingDecisionLog < ApplicationRecord
  belongs_to :user
  belongs_to :workout_plan

  scope :recent, -> { order(created_at: :desc) }
end
