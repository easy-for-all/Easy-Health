class TrainerProfile < ApplicationRecord
  belongs_to :user

  STATUSES = %w[active inactive].freeze

  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: true

  def active?
    status == "active"
  end
end
