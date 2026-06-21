require "rails_helper"

RSpec.describe CommunityPost, type: :model do
  describe "for_feed scope" do
    it "includes posts from public community-enabled users" do
      user = create(:user, community_enabled: true, profile_visibility: "public")
      post = create(:community_post, user: user)

      expect(CommunityPost.for_feed).to include(post)
    end

    it "excludes posts from private users" do
      user = create(:user, community_enabled: false, profile_visibility: "private")
      post = create(:community_post, user: user)

      expect(CommunityPost.for_feed).not_to include(post)
    end

    it "excludes posts from users with community_enabled=false even if profile is public" do
      user = create(:user, community_enabled: false, profile_visibility: "public")
      post = create(:community_post, user: user)

      expect(CommunityPost.for_feed).not_to include(post)
    end

    it "excludes posts with visibility=private" do
      user = create(:user, community_enabled: true, profile_visibility: "public")
      post = create(:community_post, user: user, visibility: "private")

      expect(CommunityPost.for_feed).not_to include(post)
    end
  end

  describe "automatic creation on WorkoutSession" do
    it "creates a community post when user has community_enabled and show_workouts" do
      user = create(:user, community_enabled: true)
      user.public_profile.update!(show_workout_count: true, show_streak: true)
      # show_workouts corresponds to show_workout_count in public_profile
      user.public_profile.update!(show_workout_count: true)

      expect {
        WorkoutSession.create!(
          user: user,
          completed_at: Time.current,
          duration_minutes: 45,
        )
      }.to change { CommunityPost.count }.by(1)

      post = CommunityPost.last
      expect(post.user).to eq(user)
      expect(post.post_type).to eq("workout_completed")
    end

    it "does NOT create a community post when community_enabled is false" do
      user = create(:user, community_enabled: false)

      expect {
        WorkoutSession.create!(
          user: user,
          completed_at: Time.current,
          duration_minutes: 30,
        )
      }.not_to change { CommunityPost.count }
    end

    it "creates streak_achieved post when streak >= 3" do
      user = create(:user, community_enabled: true)
      user.public_profile.update!(show_workout_count: true)

      # Create 2 previous sessions on consecutive days
      2.downto(1) do |days_ago|
        WorkoutSession.create!(
          user: user,
          completed_at: days_ago.days.ago,
          duration_minutes: 30,
        )
      end

      # 3rd session today should trigger streak_achieved
      WorkoutSession.create!(
        user: user,
        completed_at: Time.current,
        duration_minutes: 30,
      )

      streak_post = CommunityPost.where(user: user, post_type: "streak_achieved").last
      expect(streak_post).to be_present
    end
  end

  describe "validations" do
    it "requires valid post_type" do
      post = build(:community_post, post_type: "invalid_type")
      expect(post).not_to be_valid
    end

    it "requires valid visibility" do
      post = build(:community_post, visibility: "friends_only")
      expect(post).not_to be_valid
    end
  end
end
