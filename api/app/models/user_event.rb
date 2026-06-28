class UserEvent < ApplicationRecord
  DELIVERY_STATUSES = %w[pending delivered failed disabled].freeze

  belongs_to :user

  validates :event_name, presence: true
  validates :make_delivery_status, inclusion: { in: DELIVERY_STATUSES }

  scope :pending_make_delivery, -> { where(make_delivery_status: "pending") }
  scope :failed_make_delivery, -> { where(make_delivery_status: "failed") }
end
