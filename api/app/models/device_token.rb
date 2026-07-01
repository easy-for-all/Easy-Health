class DeviceToken < ApplicationRecord
  PLATFORMS = %w[android ios].freeze

  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :platform, inclusion: { in: PLATFORMS }
end
