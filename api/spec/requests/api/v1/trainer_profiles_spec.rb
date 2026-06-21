require "rails_helper"

RSpec.describe "Api::V1::TrainerProfiles", type: :request do
  let(:personal) { create(:user, account_type: "personal_trainer") }
  let(:regular)  { create(:user, account_type: "regular") }

  describe "POST /api/v1/trainer/profile" do
    context "as personal trainer" do
      before { sign_in personal }

      it "creates a trainer profile" do
        expect {
          post "/api/v1/trainer/profile",
               params: { display_name: "João PT", bio: "10 anos de experiência", cref: "123456-G/SP" }.to_json,
               headers: { "Content-Type" => "application/json" }
        }.to change { TrainerProfile.count }.by(1)

        expect(response).to have_http_status(:created)
        data = JSON.parse(response.body)
        expect(data["display_name"]).to eq("João PT")
        expect(data["cref"]).to eq("123456-G/SP")
      end

      it "does not allow duplicate profile" do
        TrainerProfile.create!(user: personal, display_name: "João PT")

        post "/api/v1/trainer/profile",
             params: { display_name: "João PT v2" }.to_json,
             headers: { "Content-Type" => "application/json" }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "as regular user" do
      before { sign_in regular }

      it "returns forbidden" do
        post "/api/v1/trainer/profile",
             params: { display_name: "Fake PT" }.to_json,
             headers: { "Content-Type" => "application/json" }
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PATCH /api/v1/trainer/profile" do
    before { sign_in personal }

    it "updates an existing profile" do
      TrainerProfile.create!(user: personal, display_name: "João PT", bio: "Especialista")

      patch "/api/v1/trainer/profile",
            params: { bio: "Especialista em força" }.to_json,
            headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["bio"]).to eq("Especialista em força")
    end
  end

  describe "GET /api/v1/trainer/profile" do
    before { sign_in personal }

    it "returns profile when exists" do
      TrainerProfile.create!(user: personal, display_name: "João PT")

      get "/api/v1/trainer/profile"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["display_name"]).to eq("João PT")
    end

    it "returns nil profile when not created" do
      get "/api/v1/trainer/profile"
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["profile"]).to be_nil
    end
  end
end
