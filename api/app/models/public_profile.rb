class PublicProfile < ApplicationRecord
  belongs_to :user

  validates :user_id, uniqueness: true

  def visible_fields
    {
      display_name: display_name.presence || user.name,
      avatar_url: avatar_visible ? user.avatar_url : nil,
      public_bio: public_bio,
      show_workout_count: show_workout_count,
      show_streak: show_streak,
      show_points: show_points,
      show_badges: show_badges
    }
  end
end
