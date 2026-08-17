require "rails_helper"

# Contrato do PR 0: o shell iOS carrega os assets do próprio IPA, então a origem
# é capacitor://localhost e o cookie SameSite=Lax não viaja. Estes specs provam
# que o caminho de bearer token funciona E que Web/Android não mudaram.
RSpec.describe "Mobile session authentication", type: :request do
  let(:password) { "senha-super-secreta-1" }
  let!(:user) { create(:user, password: password, password_confirmation: password) }

  def bearer(token)
    { "Authorization" => "Bearer #{token}" }
  end

  describe "issuing" do
    it "returns a token when the client opts in" do
      post "/api/v1/auth/sign_in",
        params: { email: user.email, password: password },
        headers: { "X-EasyHealth-Mobile-Session" => "1", "X-Platform" => "ios" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["mobile_session_token"]).to start_with("ehs_")
      expect(MobileSession.last).to have_attributes(user_id: user.id, platform: "ios")
    end

    it "does not return a token for a normal web login" do
      post "/api/v1/auth/sign_in", params: { email: user.email, password: password }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key("mobile_session_token")
      expect(MobileSession.count).to eq(0)
    end

    it "carries installation and version correlation when present" do
      post "/api/v1/auth/sign_in",
        params: { email: user.email, password: password },
        headers: {
          "X-EasyHealth-Mobile-Session" => "1", "X-Platform" => "ios",
          "X-Installation-Id" => "inst-abc", "X-App-Version" => "2.0.0"
        }

      expect(MobileSession.last).to have_attributes(
        installation_id: "inst-abc", app_version: "2.0.0"
      )
    end

    it "still logs the user in when the platform header is unusable" do
      post "/api/v1/auth/sign_in",
        params: { email: user.email, password: password },
        headers: { "X-EasyHealth-Mobile-Session" => "1", "X-Platform" => "web" }

      # Login succeeded; only the (unusable) token issue was skipped.
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key("mobile_session_token")
      expect(MobileSession.count).to eq(0)
    end

    it "issues a token on sign_up as well" do
      post "/api/v1/auth/sign_up",
        params: {
          name: "Nova", email: "nova@example.com",
          password: password, password_confirmation: password,
          terms_accepted: true, privacy_accepted: true
        },
        headers: { "X-EasyHealth-Mobile-Session" => "1", "X-Platform" => "ios" }

      expect(response).to have_http_status(:created)
      expect(response.parsed_body["mobile_session_token"]).to start_with("ehs_")
    end
  end

  describe "authenticating" do
    it "authenticates a protected endpoint with the bearer token alone" do
      token = MobileSession.issue_for!(user: user, platform: "ios")

      get "/api/v1/auth/me", headers: bearer(token)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(user.id)
    end

    it "authenticates a BaseController endpoint too" do
      token = MobileSession.issue_for!(user: user, platform: "ios")

      get "/api/v1/billing/status", headers: bearer(token)

      expect(response).to have_http_status(:ok)
    end

    it "rejects a revoked token with a code the client can act on" do
      token = MobileSession.issue_for!(user: user, platform: "ios")
      MobileSession.last.revoke!(reason: "user_signout")

      get "/api/v1/auth/me", headers: bearer(token)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("invalid_mobile_session")
    end

    it "rejects an expired token" do
      token = MobileSession.issue_for!(user: user, platform: "ios")
      MobileSession.last.update_columns(expires_at: 1.second.ago)

      get "/api/v1/auth/me", headers: bearer(token)

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a token for an anonymized account" do
      token = MobileSession.issue_for!(user: user, platform: "ios")
      user.update_columns(anonymized_at: Time.current)

      get "/api/v1/auth/me", headers: bearer(token)

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "not disturbing existing clients" do
    it "leaves the cookie session path untouched when no bearer is sent" do
      sign_in user

      get "/api/v1/auth/me"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(user.id)
    end

    # AnonymousAuthentication and the Make integrations also use
    # `Authorization: Bearer`. Without the ehs_ prefix guard, this concern would
    # intercept their tokens and 401 them before the right concern ever ran.
    it "ignores a bearer token that is not a mobile session" do
      sign_in user

      get "/api/v1/auth/me", headers: bearer("some-other-integration-token")

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["id"]).to eq(user.id)
    end

    it "does not claim a non-mobile bearer as its own failure" do
      get "/api/v1/auth/me", headers: bearer("anon.token.value")

      # Falls through to whatever Devise already did for an unauthenticated
      # request. What matters is that this concern did not intercept it.
      expect(response.parsed_body["error"]).not_to eq("invalid_mobile_session")
      expect(MobileSession.count).to eq(0)
    end
  end

  describe "revocation" do
    it "revokes every session of the user on sign out" do
      first = MobileSession.issue_for!(user: user, platform: "ios")
      second = MobileSession.issue_for!(user: user, platform: "android")

      delete "/api/v1/auth/sign_out", headers: bearer(first)
      expect(response).to have_http_status(:ok)

      expect(MobileSession.authenticate(first)).to be_nil
      expect(MobileSession.authenticate(second)).to be_nil
    end

    it "revokes sessions when the account is deleted" do
      token = MobileSession.issue_for!(user: user, platform: "ios")

      AccountDeletionService.new(user).call

      expect(MobileSession.authenticate(token)).to be_nil
      expect(MobileSession.last.revocation_reason).to eq("account_deleted")
    end
  end
end
