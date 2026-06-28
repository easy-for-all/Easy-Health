class UserSegment < ApplicationRecord
  SEGMENTS = %w[
    trial_active
    trial_expiring_soon
    trial_expired
    subscriber_active
    subscriber_canceled
    never_created_workout
    workout_created_not_started
    first_workout_done
    active_user
    inactive_3_days
    inactive_7_days
    inactive_15_days
    high_intent_trial
    churn_risk
    returning_user
    uploaded_body_photo
    no_body_photo
    completed_partial_recently
  ].freeze

  belongs_to :user

  validates :segment_name, presence: true, inclusion: { in: SEGMENTS }
  validates :segment_name, uniqueness: { scope: :user_id }

  scope :active, -> { where(active: true) }
end
