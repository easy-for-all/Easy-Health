class AiWorkoutChatConversation < ApplicationRecord
  STATUSES = %w[collecting previewing confirmed abandoned].freeze
  ACTIVE_STATUSES = %w[collecting previewing].freeze

  belongs_to :user

  validates :status, inclusion: { in: STATUSES }

  scope :active_for, ->(user) { where(user: user, status: ACTIVE_STATUSES).order(created_at: :desc) }

  def workout_plan
    return nil unless workout_plan_id
    WorkoutPlan.find_by(id: workout_plan_id)
  end
end
