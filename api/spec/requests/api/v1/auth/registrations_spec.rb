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

    # signup_source answers "where was this ACCOUNT CREATED from", which nothing
    # recorded before. The signal is the X-Platform header the client already
    # sends on every request; consent_source cannot be reused because it is
    # hardcoded "web" here regardless of the real platform.
    describe "signup_source" do
      let(:consent) { { terms_accepted: true, privacy_accepted: true } }

      it "records android when the Android client's X-Platform header says so" do
        post "/api/v1/auth/sign_up",
             params: base_params.merge(consent),
             headers: { "X-Platform" => "android" },
             as: :json

        expect(response).to have_http_status(:created)
        expect(User.find_by(email: "signup@example.com").signup_source).to eq("android")
      end

      it "records web and pwa from their own header values" do
        post "/api/v1/auth/sign_up",
             params: base_params.merge(consent),
             headers: { "X-Platform" => "pwa" },
             as: :json

        expect(User.find_by(email: "signup@example.com").signup_source).to eq("pwa")
      end

      it "falls back to unknown when no platform header arrives" do
        post "/api/v1/auth/sign_up", params: base_params.merge(consent), as: :json

        expect(response).to have_http_status(:created)
        expect(User.find_by(email: "signup@example.com").signup_source).to eq("unknown")
      end

      # Fail-open: the origin is a diagnostic dimension, so a hostile or
      # malformed header must degrade to "unknown" and NEVER turn a signup into
      # a 422/500.
      it "drops a hostile header value instead of rejecting the signup" do
        post "/api/v1/auth/sign_up",
             params: base_params.merge(consent),
             headers: { "X-Platform" => "android'; DROP TABLE users--" },
             as: :json

        expect(response).to have_http_status(:created)
        expect(User.find_by(email: "signup@example.com").signup_source).to eq("unknown")
      end

      it "does not touch consent_source, which keeps answering its own question" do
        post "/api/v1/auth/sign_up",
             params: base_params.merge(consent),
             headers: { "X-Platform" => "android" },
             as: :json

        expect(User.find_by(email: "signup@example.com").consent_source).to eq("web")
      end
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
