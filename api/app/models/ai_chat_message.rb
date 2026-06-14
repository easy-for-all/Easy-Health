class AiChatMessage < ApplicationRecord
  belongs_to :user

  scope :for_session, ->(sid) { where(session_id: sid).order(:created_at) }
  scope :recent,      -> { order(created_at: :desc) }

  validates :role,    inclusion: { in: %w[user assistant] }
  validates :content, presence: true
end
