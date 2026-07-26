require "rails_helper"

RSpec.describe Api::V1::Auth::OmniauthCallbacksController, type: :controller do
  include Devise::Test::ControllerHelpers

  let(:auth_hash) do
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-123",
      info: {
        email: "google@example.com",
        name: "Google User",
        image: nil
      }
    )
  end

  before do
    request.env["devise.mapping"] = Devise.mappings[:user]
    request.env["omniauth.auth"] = auth_hash
  end

  it "keeps the web flow redirecting to the app dashboard" do
    request.env["omniauth.params"] = { "terms_accepted" => "1", "privacy_accepted" => "1" }

    get :google_oauth2

    expect(response).to redirect_to("https://easyhealth.art/onboarding")
    expect(MobileAuthCode.count).to eq(0)
  end

  it "creates the account from the consent carried in omniauth.params" do
    request.env["omniauth.params"] = {
      "terms_accepted" => "1", "privacy_accepted" => "1", "marketing_consent" => "0"
    }

    expect { get :google_oauth2 }.to change(User, :count).by(1)

    user = User.find_by(email: "google@example.com")
    expect(user.consent_source).to eq("web")
    expect(user.marketing_consent).to be(false)
  end

  it "refuses to create an account when omniauth.params carries no consent" do
    expect { get :google_oauth2 }.not_to change(User, :count)

    expect(response).to redirect_to("https://easyhealth.art/sign-up?error=consent_required&provider=google")
  end

  it "signs an existing user in without requiring consent again" do
    accepted_at = 3.days.ago
    existing = create(:user, email: "google@example.com", terms_accepted_at: accepted_at,
                             created_at: 1.day.ago)

    expect { get :google_oauth2 }.not_to change(User, :count)

    expect(response).to redirect_to("https://easyhealth.art/dashboard")
    expect(existing.reload.terms_accepted_at).to be_within(1.second).of(accepted_at)
  end

  it "redirects the android flow to the mobile callback with a one-time code" do
    request.env["omniauth.params"] = { "terms_accepted" => "1", "privacy_accepted" => "1" }

    get :google_oauth2_mobile

    expect(response).to have_http_status(:found)
    location = URI.parse(response.headers["Location"])
    expect("#{location.scheme}://#{location.host}#{location.path}").to eq("https://easyhealth.art/mobile-auth/callback")
    expect(location.query).to include("platform=android")
    expect(MobileAuthCode.count).to eq(1)
    expect(MobileAuthCode.last.code_digest).to be_present
  end
end
