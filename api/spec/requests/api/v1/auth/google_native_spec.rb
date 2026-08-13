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

    describe "signup_source" do
      let(:consent) { { terms_accepted: true, privacy_accepted: true } }

      before { allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims) }

      it "records android from the X-Platform header" do
        post "/api/v1/auth/google/native",
             params: { id_token: "valid.jwt" }.merge(consent),
             headers: { "X-Platform" => "android" },
             as: :json

        expect(response).to have_http_status(:ok)
        expect(User.find_by(email: "native@example.com").signup_source).to eq("android")
      end

      it "falls back to the client-declared platform param when no header arrives" do
        post "/api/v1/auth/google/native",
             params: { id_token: "valid.jwt", platform: "android" }.merge(consent),
             as: :json

        expect(User.find_by(email: "native@example.com").signup_source).to eq("android")
      end

      # Unlike consent_source (which defaults to "android" on this endpoint),
      # signup_source is never fabricated: an unattributable signup is worth more
      # as "unknown" than as an invented platform.
      it "stays unknown when neither the header nor the param says anything" do
        post "/api/v1/auth/google/native", params: { id_token: "valid.jwt" }.merge(consent), as: :json

        expect(response).to have_http_status(:ok)
        expect(User.find_by(email: "native@example.com").signup_source).to eq("unknown")
      end
    end

    # `new_user` drives the Android sign_up-vs-login conversion sent to Firebase,
    # so it has to mean "this request inserted the row" and nothing else. It used
    # to be inferred from the account's age (created_at > 5.minutes.ago &&
    # health_profile.nil?), which reported the SAME account as new more than once.
    describe "new_user" do
      let(:consent) { { terms_accepted: true, privacy_accepted: true } }

      before { allow(Auth::GoogleIdTokenVerifier).to receive(:verify!).and_return(claims) }

      it "is true when the request creates the account" do
        expect do
          post "/api/v1/auth/google/native",
               params: { id_token: "valid.jwt", platform: "android" }.merge(consent), as: :json
        end.to change(User, :count).by(1)

        expect(response.parsed_body["new_user"]).to be(true)
      end

      it "is false when the request reuses an existing account" do
        create(:user, email: "native@example.com")

        post "/api/v1/auth/google/native", params: { id_token: "valid.jwt", platform: "android" }, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["new_user"]).to be(false)
      end

      # The regression the old heuristic could not survive: someone who signs up
      # and comes straight back — before finishing onboarding, so still without a
      # health_profile, and well inside the five-minute window — was counted as a
      # second brand-new account.
      it "is false when the same account authenticates again seconds later" do
        post "/api/v1/auth/google/native",
             params: { id_token: "valid.jwt", platform: "android" }.merge(consent), as: :json
        expect(response.parsed_body["new_user"]).to be(true)

        user = User.find_by(email: "native@example.com")
        expect(user.health_profile).to be_nil
        expect(user.created_at).to be > 5.minutes.ago

        expect do
          post "/api/v1/auth/google/native",
               params: { id_token: "valid.jwt", platform: "android" }.merge(consent), as: :json
        end.not_to change(User, :count)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["new_user"]).to be(false)
      end

      # An e-mail account that had never used Google gains the identity here. The
      # row is updated, not inserted, so this is a login.
      it "is false when a pre-existing account merely gains the Google identity" do
        existing = create(:user, email: "native@example.com", provider: nil, uid: nil)

        post "/api/v1/auth/google/native", params: { id_token: "valid.jwt", platform: "android" }, as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["new_user"]).to be(false)
        expect(existing.reload.provider).to eq("google_oauth2")
        expect(existing.uid).to eq("google-sub-123")
      end
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
