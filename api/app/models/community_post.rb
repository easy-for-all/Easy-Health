class CommunityPost < ApplicationRecord
  belongs_to :user
  has_many :community_reactions, dependent: :destroy
  has_many :community_comments, dependent: :destroy

  POST_TYPES = %w[workout_completed streak_achieved achievement_unlocked progress_update].freeze

  validates :post_type, inclusion: { in: POST_TYPES }
  validates :visibility, inclusion: { in: %w[public private] }

  scope :for_feed, -> {
    joins(user: :public_profile)
      .where(users: { community_enabled: true })
      .where.not(users: { profile_visibility: "private" })
      .where(visibility: "public")
      .order(created_at: :desc)
  }

  scope :by_user, ->(user_id) { where(user_id: user_id) }
end
