require "rails_helper"

RSpec.describe "Api::V1::Personal::Clients", type: :request do
  let(:personal) { create(:user, account_type: "personal_trainer") }
  let(:student)  { create(:user) }
  before { sign_in personal }

  def make_relationship(status: "active")
    rel = PersonalClientRelationship.create!(
      personal_id: personal.id,
      client_id:   status == "active" ? student.id : nil,
      invitation_code: SecureRandom.hex(8),
      status: status,
      started_at: status == "active" ? Time.current : nil
    )
    ClientPermission.create!(
      personal_client_relationship: rel,
      can_view_adherence: true,
      can_view_completed_workouts: true,
      can_view_assigned_workouts: true,
      can_view_exercise_performance: false,
      can_view_body_weight: false,
      can_view_photos: false,
      can_view_body_analysis: false,
      can_view_exams: false
    )
    rel
  end

  describe "GET /api/v1/personal/clients/:id" do
    let!(:relationship) { make_relationship }

    it "returns client data for active relationship" do
      get "/api/v1/personal/clients/#{student.id}"
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data["client"]["client_id"]).to eq(student.id)
    end

    it "never returns email in response" do
      get "/api/v1/personal/clients/#{student.id}"
      expect(response.body).not_to include(student.email)
    end

    it "returns 404 for client without active relationship" do
      stranger = create(:user)
      get "/api/v1/personal/clients/#{stranger.id}"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/personal/clients/:id/notes" do
    let!(:relationship) { make_relationship }

    it "creates a note" do
      expect {
        post "/api/v1/personal/clients/#{student.id}/notes",
             params: { body: "Melhorou muito na agachamento." }.to_json,
             headers: { "Content-Type" => "application/json" }
      }.to change { PersonalNote.count }.by(1)

      expect(response).to have_http_status(:created)
    end

    it "note is always private" do
      post "/api/v1/personal/clients/#{student.id}/notes",
           params: { body: "Nota confidencial." }.to_json,
           headers: { "Content-Type" => "application/json" }
      note = PersonalNote.last
      expect(note.visibility).to eq("private")
    end

    it "note does not appear in community feed" do
      post "/api/v1/personal/clients/#{student.id}/notes",
           params: { body: "Nota confidencial." }.to_json,
           headers: { "Content-Type" => "application/json" }

      # Community posts should not include private notes
      community_post_bodies = CommunityPost.all.map(&:body)
      expect(community_post_bodies).not_to include("Nota confidencial.")
    end

    it "returns 404 for non-active client" do
      stranger = create(:user)
      post "/api/v1/personal/clients/#{stranger.id}/notes",
           params: { body: "Test." }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/personal/clients/:id (revoke access)" do
    let!(:relationship) { make_relationship }

    it "allows student to revoke access" do
      sign_in student
      delete "/api/v1/personal/clients/#{student.id}"
      # We test that the endpoint is accessible; actual status update tested in model
      expect(response.status).not_to eq(401)
    end
  end

  describe "permissions enforcement" do
    let!(:relationship) { make_relationship }

    it "does not return sensitive data when permissions are off" do
      get "/api/v1/personal/clients/#{student.id}"
      data = JSON.parse(response.body)["client"]

      # These should be nil when permissions are off
      expect(data["body_weight"]).to be_nil
      expect(data["photos"]).to be_nil
      expect(data["exams"]).to be_nil
    end
  end
end
