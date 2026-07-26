require "rails_helper"

# End-to-end proof that consent survives the whole web round-trip:
#
#   GET /auth/google/web?terms_accepted=1…
#     -> GoogleOauthController#web (allow-listed redirect)
#     -> OmniAuth request phase, which stores request.GET in the Rack session
#     -> callback, where the strategy hands it back as env["omniauth.params"]
#
# The controller spec injects omniauth.params directly and therefore never
# noticed that the router-level redirect was throwing the query string away.
# This spec walks the real redirects, so that regression cannot come back.
RSpec.describe "Google web consent transport", type: :request do
  let(:auth_hash) do
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-transport-1",
      info: { email: "transport@example.com", name: "Transport User", image: nil }
    )
  end

  around do |example|
    previous_test_mode = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = auth_hash
    example.run
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.test_mode = previous_test_mode
  end

  # Walks: /auth/google/web -> /users/auth/google_oauth2 -> callback.
  def complete_google_web_flow(params = {})
    get "/auth/google/web", params: params
    follow_redirect! # request phase
    follow_redirect! # callback
  end

  it "creates the account when the consent params make it through" do
    expect do
      complete_google_web_flow(terms_accepted: "1", privacy_accepted: "1", marketing_consent: "1")
    end.to change(User, :count).by(1)

    user = User.find_by(email: "transport@example.com")
    expect(user.terms_accepted_at).to be_present
    expect(user.privacy_policy_accepted_at).to be_present
    expect(user.terms_version).to eq(User::CURRENT_TERMS_VERSION)
    expect(user.consent_source).to eq("web")
    expect(user.marketing_consent).to be(true)
    expect(response).to redirect_to("https://easyhealth.art/onboarding")
  end

  it "stores marketing_consent as false when the box was left unchecked" do
    complete_google_web_flow(terms_accepted: "1", privacy_accepted: "1", marketing_consent: "0")

    expect(User.find_by(email: "transport@example.com").marketing_consent).to be(false)
  end

  it "refuses to create the account when consent was not given, and points at sign-up" do
    expect do
      complete_google_web_flow
    end.not_to change(User, :count)

    expect(response).to redirect_to("https://easyhealth.art/sign-up?error=consent_required&provider=google")
  end

  it "refuses when only the terms were accepted" do
    expect do
      complete_google_web_flow(terms_accepted: "1")
    end.not_to change(User, :count)

    expect(response).to redirect_to("https://easyhealth.art/sign-up?error=consent_required&provider=google")
  end

  it "lets an existing account sign in without asking for consent again" do
    # created_at matters: the callback treats a just-created profile-less account
    # as still onboarding, so an "existing" user must not look brand new.
    existing = create(:user, email: "transport@example.com", terms_accepted_at: 3.days.ago,
                             created_at: 1.day.ago)

    expect { complete_google_web_flow }.not_to change(User, :count)

    expect(response).to redirect_to("https://easyhealth.art/dashboard")
    expect(existing.reload.provider).to eq("google_oauth2")
  end
end
