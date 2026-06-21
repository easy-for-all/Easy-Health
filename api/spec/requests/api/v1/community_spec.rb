require "rails_helper"

RSpec.describe "Api::V1::Community", type: :request do
  let(:viewer) { create(:user) }
  before { sign_in viewer }

  def make_public_user(attrs = {})
    u = create(:user, community_enabled: true, profile_visibility: "public", **attrs)
    u.public_profile.update!(show_workout_count: true, show_streak: true)
    u
  end

  describe "GET /api/v1/community/feed" do
    context "private user" do
      it "does not appear in feed" do
        private_user = create(:user, community_enabled: false, profile_visibility: "private")
        create(:community_post, user: private_user)

        get "/api/v1/community/feed"
        expect(response).to have_http_status(:ok)
        ids = JSON.parse(response.body)["posts"].map { |p| p["id"] }
        expect(ids).to be_empty
      end
    end

    context "public user with community_enabled" do
      it "appears in feed" do
        author = make_public_user
        post = create(:community_post, user: author)

        get "/api/v1/community/feed"
        expect(response).to have_http_status(:ok)
        ids = JSON.parse(response.body)["posts"].map { |p| p["id"] }
        expect(ids).to include(post.id)
      end

      it "never returns email in response" do
        author = make_public_user
        create(:community_post, user: author)

        get "/api/v1/community/feed"
        body = response.body
        expect(body).not_to include(author.email)
      end

      it "does not include viewer's own posts" do
        viewer.update!(community_enabled: true, profile_visibility: "public")
        create(:community_post, user: viewer)

        get "/api/v1/community/feed"
        ids = JSON.parse(response.body)["posts"].map { |p| p["id"] }
        expect(ids).to be_empty
      end
    end
  end

  describe "POST /api/v1/community/posts/:id/reactions" do
    let(:author) { make_public_user }
    let!(:post_record) { create(:community_post, user: author) }

    it "creates a reaction" do
      expect {
        post "/api/v1/community/posts/#{post_record.id}/reactions", params: { reaction_type: "congrats" }.to_json,
             headers: { "Content-Type" => "application/json" }
      }.to change { CommunityReaction.count }.by(1)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["reacted"]).to be true
      expect(data["reaction_count"]).to eq(1)
    end

    it "is idempotent (no duplicate reactions)" do
      post "/api/v1/community/posts/#{post_record.id}/reactions",
           params: { reaction_type: "congrats" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect {
        post "/api/v1/community/posts/#{post_record.id}/reactions",
             params: { reaction_type: "congrats" }.to_json,
             headers: { "Content-Type" => "application/json" }
      }.not_to change { CommunityReaction.count }
    end
  end

  describe "DELETE /api/v1/community/posts/:id/reactions" do
    let(:author) { make_public_user }
    let!(:post_record) { create(:community_post, user: author) }

    it "removes a reaction" do
      create(:community_post, user: author) # unused
      CommunityReaction.create!(user: viewer, community_post: post_record, reaction_type: "congrats")

      expect {
        delete "/api/v1/community/posts/#{post_record.id}/reactions"
      }.to change { CommunityReaction.count }.by(-1)

      data = JSON.parse(response.body)
      expect(data["reacted"]).to be false
    end
  end

  describe "POST /api/v1/community/posts/:id/comments" do
    let(:author) { make_public_user }
    let!(:post_record) { create(:community_post, user: author) }

    it "creates a comment" do
      expect {
        post "/api/v1/community/posts/#{post_record.id}/comments",
             params: { body: "Ótimo treino!" }.to_json,
             headers: { "Content-Type" => "application/json" }
      }.to change { CommunityComment.count }.by(1)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)
      expect(data["body"]).to eq("Ótimo treino!")
    end

    it "rejects empty body" do
      post "/api/v1/community/posts/#{post_record.id}/comments",
           params: { body: "  " }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/community/comments/:id" do
    let(:author) { make_public_user }
    let(:post_record) { create(:community_post, user: author) }

    it "deletes own comment" do
      comment = CommunityComment.create!(user: viewer, community_post: post_record, body: "test")
      expect {
        delete "/api/v1/community/comments/#{comment.id}"
      }.to change { CommunityComment.count }.by(-1)
      expect(response).to have_http_status(:ok)
    end

    it "cannot delete other user comment" do
      other = create(:user)
      comment = CommunityComment.create!(user: other, community_post: post_record, body: "test")
      expect {
        delete "/api/v1/community/comments/#{comment.id}"
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
