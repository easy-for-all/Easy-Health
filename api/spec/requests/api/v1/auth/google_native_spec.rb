require "rails_helper"

RSpec.describe "Api::V1::Auth::GoogleNative", type: :request do
  let(:claims) do
    {
      "aud" => "web-client-id",
      "sub" => "google-sub-123",
      "email" => "native@example.com",
      "name" => "Native User",
      "picture" => nil
    }
  end

  describe "POST /api/v1/auth/google/native" do
    it "creates and signs in a new user from a valid id token when consent is given" do
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims)

      expect do
        post "/api/v1/auth/google/native",
             params: { id_token: "valid.jwt", platform: "android", terms_accepted: true, privacy_accepted: true },
             as: :json
      end.to change(User, :count).by(1)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["email"]).to eq("native@example.com")
      expect(body["new_user"]).to be(true)

      user = User.find_by(email: "native@example.com")
      expect(user.terms_accepted_at).to be_present
      expect(user.privacy_policy_accepted_at).to be_present
      expect(user.terms_version).to eq(User::CURRENT_TERMS_VERSION)
      expect(user.privacy_policy_version).to eq(User::CURRENT_PRIVACY_POLICY_VERSION)
      expect(user.consent_source).to eq("android")

      get "/api/v1/auth/me"
      expect(response).to have_http_status(:ok)
    end

    it "refuses to create a new user without consent" do
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims)

      expect do
        post "/api/v1/auth/google/native", params: { id_token: "valid.jwt", platform: "android" }, as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error_code"]).to eq("consent_required")
    end

    it "lets an existing user sign in without consent and does not overwrite acceptance dates" do
      accepted_at = 3.days.ago
      existing = create(:user, email: "native@example.com", terms_accepted_at: accepted_at,
                               privacy_policy_accepted_at: accepted_at, terms_version: "1.0")
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims)

      expect do
        post "/api/v1/auth/google/native", params: { id_token: "valid.jwt", platform: "android" }, as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(existing.reload.terms_accepted_at).to be_within(1.second).of(accepted_at)
    end

    it "reuses an existing user matched by email" do
      existing = create(:user, email: "native@example.com")
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims)

      expect do
        post "/api/v1/auth/google/native", params: { id_token: "valid.jwt", platform: "android" }, as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(existing.id)
    end

    it "rejects an invalid id token with 401" do
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!)
        .and_raise(Auth::GoogleIdTokenVerifier::VerificationError, "bad aud")

      post "/api/v1/auth/google/native", params: { id_token: "bad.jwt", platform: "android" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error_code"]).to eq("invalid_token")
    end
  end
end
