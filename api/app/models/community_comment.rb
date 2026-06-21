class CommunityComment < ApplicationRecord
  belongs_to :user
  belongs_to :community_post

  validates :body, presence: true, length: { maximum: 500 }
end
