class HealthDataPoint < ApplicationRecord
  belongs_to :user
  belongs_to :user_media, optional: true

  STATUSES    = %w[pending_review confirmed ignored saved_advanced].freeze
  SOURCE_TYPES = %w[exam body_photo manual].freeze

  validates :field_name,  presence: true
  validates :source_type, inclusion: { in: SOURCE_TYPES }
  validates :status,      inclusion: { in: STATUSES }

  scope :pending, -> { where(status: "pending_review") }
end
