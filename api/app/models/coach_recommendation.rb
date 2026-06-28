class CoachRecommendation < ApplicationRecord
  TYPES = %w[
    weight_progression weight_reduction add_exercise
    reduce_volume increase_volume recovery_adjustment technique_tip
  ].freeze
  STATUSES = %w[pending accepted dismissed expired].freeze

  belongs_to :user
  belongs_to :exercise, optional: true

  validates :recommendation_type, inclusion: { in: TYPES }
  validates :status,              inclusion: { in: STATUSES }
  validates :user,                presence: true

  scope :pending,  -> { where(status: "pending") }
  scope :for_user, ->(user) { where(user: user) }

  def accept!(extra_metadata = {})
    update!(
      status:      "accepted",
      accepted_at: Time.current,
      metadata:    metadata.merge(extra_metadata)
    )
  end

  def dismiss!
    update!(status: "dismissed", dismissed_at: Time.current)
  end
end
