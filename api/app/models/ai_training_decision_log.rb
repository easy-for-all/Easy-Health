class AiTrainingDecisionLog < ApplicationRecord
  belongs_to :user
  belongs_to :workout_plan
  belongs_to :ai_prompt_version, optional: true

  STATUSES = %w[success fallback_used validation_failed error].freeze

  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  scope :recent,     -> { order(created_at: :desc) }
  scope :successful, -> { where(status: "success") }
  scope :today,      -> { where(created_at: Time.current.all_day) }
end
