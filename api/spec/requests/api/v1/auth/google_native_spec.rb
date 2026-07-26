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
      body = response.parsed_body
      expect(body["error_code"]).to eq("consent_required")
      # The login screen keys off `action` to offer the sign-up route instead of
      # leaving the user on a dead-end error message.
      expect(body["action"]).to eq("sign_up")
      expect(body["message"]).to be_present
    end

    it "refuses when only the terms were accepted" do
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims)

      expect do
        post "/api/v1/auth/google/native",
             params: { id_token: "valid.jwt", platform: "android", terms_accepted: true, privacy_accepted: false },
             as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error_code"]).to eq("consent_required")
    end

    it "refuses when only the privacy policy was accepted" do
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims)

      expect do
        post "/api/v1/auth/google/native",
             params: { id_token: "valid.jwt", platform: "android", terms_accepted: false, privacy_accepted: true },
             as: :json
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error_code"]).to eq("consent_required")
    end

    it "stores marketing_consent as false when the user declined it" do
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims)

      post "/api/v1/auth/google/native",
           params: { id_token: "valid.jwt", platform: "android", terms_accepted: true,
                     privacy_accepted: true, marketing_consent: false },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(User.find_by(email: "native@example.com").marketing_consent).to be(false)
    end

    it "never opts the user into marketing by omission" do
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims)

      post "/api/v1/auth/google/native",
           params: { id_token: "valid.jwt", platform: "android", terms_accepted: true, privacy_accepted: true },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(User.find_by(email: "native@example.com").marketing_consent).to be(false)
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

    it "links the installation sent in X-Installation-Id within the sign_in cycle" do
      existing = create(:user, email: "native@example.com")
      installation = create(:app_installation, :anonymous)
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims)

      post "/api/v1/auth/google/native",
           params: { id_token: "valid.jwt", platform: "android" },
           headers: { "X-Installation-Id" => installation.installation_id },
           as: :json

      expect(response).to have_http_status(:ok)
      installation.reload
      expect(installation.user_id).to eq(existing.id)
      expect(installation.last_authenticated_at).to be_present
    end

    it "does not link the installation when the token is rejected" do
      installation = create(:app_installation, :anonymous)
      allow(Auth::GoogleIdTokenVerifier).to receive(:verify!)
        .and_raise(Auth::GoogleIdTokenVerifier::VerificationError, "bad aud")

      post "/api/v1/auth/google/native",
           params: { id_token: "bad.jwt", platform: "android" },
           headers: { "X-Installation-Id" => installation.installation_id },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(installation.reload.user_id).to be_nil
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
