class UserMedia < ApplicationRecord
  belongs_to :user
  has_one_attached :file

  CATEGORIES = %w[body_photo exam].freeze

  validates :category, inclusion: { in: CATEGORIES }
  validates :captured_at, presence: true
end
