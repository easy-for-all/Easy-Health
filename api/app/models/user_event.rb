class UserEvent < ApplicationRecord
  DELIVERY_STATUSES = %w[
    pending
    sending
    accepted_by_make
    retrying
    failed_to_reach_make
    dead_letter
    disabled
    skipped
  ].freeze
  PROCESSING_STATUSES = %w[unknown received routed filtered completed failed].freeze
  ERROR_DELIVERY_STATUSES = %w[failed_to_reach_make dead_letter].freeze
  ACTIVE_DELIVERY_STATUSES = %w[pending sending retrying].freeze

  belongs_to :user

  validates :event_name, presence: true
  validates :make_delivery_status, inclusion: { in: DELIVERY_STATUSES }
  validates :make_processing_status, inclusion: { in: PROCESSING_STATUSES }

  scope :pending_make_delivery, -> { where(make_delivery_status: "pending") }
  scope :accepted_by_make, -> { where(make_delivery_status: "accepted_by_make") }
  scope :failed_make_delivery, -> { where(make_delivery_status: ERROR_DELIVERY_STATUSES) }
  scope :skipped_make_delivery, -> { where(make_delivery_status: "skipped") }
  scope :active_make_delivery, -> { where(make_delivery_status: ACTIVE_DELIVERY_STATUSES) }

  def make_delivery_channels_list
    Array(make_delivery_channels).map(&:to_s).reject(&:blank?)
  end
end
