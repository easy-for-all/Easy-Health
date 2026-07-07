class OnboardingEvent < ApplicationRecord
  belongs_to :user

  FLOWS = %w[quick complete photo_ai chat_ai legacy].freeze

  EVENT_NAMES = %w[
    onboarding_started
    onboarding_flow_selected
    onboarding_step_viewed
    onboarding_step_completed
    onboarding_step_skipped
    onboarding_abandoned
    onboarding_completed
    plan_generation_started
    plan_created
    workout_started
    workout_completed
    first_workout_completed_24h
    progressive_question_shown
    progressive_question_answered
    progressive_question_skipped
    ai_summary_generated
    ai_summary_edited
    ai_plan_accepted
    ai_plan_regenerated
    ai_plan_abandoned
  ].freeze

  validates :event_name, presence: true, inclusion: { in: EVENT_NAMES }
  validates :onboarding_flow, inclusion: { in: FLOWS }, allow_nil: true

  before_validation :set_occurred_at, on: :create

  scope :named, ->(event_name) { where(event_name: event_name) }
  scope :for_flow, ->(flow) { where(onboarding_flow: flow) }
  scope :in_period, ->(from) { where(occurred_at: from..) if from }

  private

  def set_occurred_at
    self.occurred_at ||= Time.current
  end
end
