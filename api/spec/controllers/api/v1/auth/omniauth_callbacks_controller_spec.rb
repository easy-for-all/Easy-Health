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
    get :google_oauth2

    expect(response).to redirect_to("https://easyhealth.art/onboarding")
    expect(MobileAuthCode.count).to eq(0)
  end

  it "redirects the android flow to the mobile callback with a one-time code" do
    get :google_oauth2_mobile

    expect(response).to have_http_status(:found)
    location = URI.parse(response.headers["Location"])
    expect("#{location.scheme}://#{location.host}#{location.path}").to eq("https://easyhealth.art/mobile-auth/callback")
    expect(location.query).to include("platform=android")
    expect(MobileAuthCode.count).to eq(1)
    expect(MobileAuthCode.last.code_digest).to be_present
  end
end
