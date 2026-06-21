class CommunityReaction < ApplicationRecord
  belongs_to :user
  belongs_to :community_post, counter_cache: false

  REACTION_TYPES = %w[congrats like fire].freeze

  validates :reaction_type, inclusion: { in: REACTION_TYPES }
  validates :user_id, uniqueness: { scope: :community_post_id }
end
