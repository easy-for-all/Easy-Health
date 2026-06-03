class SharedWorkout < ApplicationRecord
  belongs_to :owner, class_name: "User"

  VISIBILITIES = %w[private_link specific_users community].freeze

  validates :token, presence: true, uniqueness: true
  validates :visibility, inclusion: { in: VISIBILITIES }

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
