require "rails_helper"

RSpec.describe "Api::V1::Auth::Registrations", type: :request do
  let(:base_params) do
    { name: "New User", email: "signup@example.com", password: "supersecret", password_confirmation: "supersecret" }
  end

  describe "POST /api/v1/auth/sign_up" do
    it "creates a user and stamps consent when terms are accepted" do
      expect do
        post "/api/v1/auth/sign_up",
             params: base_params.merge(terms_accepted: true, privacy_accepted: true, marketing_consent: true),
             as: :json
      end.to change(User, :count).by(1)

      expect(response).to have_http_status(:created)
      user = User.find_by(email: "signup@example.com")
      expect(user.terms_accepted_at).to be_present
      expect(user.privacy_policy_accepted_at).to be_present
      expect(user.terms_version).to eq(User::CURRENT_TERMS_VERSION)
      expect(user.privacy_policy_version).to eq(User::CURRENT_PRIVACY_POLICY_VERSION)
      expect(user.consent_source).to eq("web")
      expect(user.marketing_consent).to be(true)
    end

    it "refuses to create a user without terms acceptance" do
      expect do
        post "/api/v1/auth/sign_up", params: base_params.merge(marketing_consent: true), as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error_code"]).to eq("consent_required")
    end
  end
end
