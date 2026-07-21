require "rails_helper"

RSpec.describe "Api::V1::App::Installations", type: :request do
  before { allow(AppInstallations::Register).to receive(:enabled?).and_return(true) }

  def payload(overrides = {})
    {
      installation_id: "inst-req-1",
      platform: "android",
      native: true,
      app_version: "1.2.0",
      app_build: "42",
      operating_system: "android",
      operating_system_version: "15",
      locale: "pt-BR",
      timezone: "America/Sao_Paulo",
      notification_permission: "granted",
      push_enabled: true,
      analytics_consent: true,
      tracking_version: 2
    }.merge(overrides)
  end

  describe "POST /api/v1/app/installations/register" do
    it "registers an anonymous installation" do
      post "/api/v1/app/installations/register", params: payload, as: :json

      expect(response).to have_http_status(:created)
      install = AppInstallation.find_by(installation_id: "inst-req-1")
      expect(install).to be_present
      expect(install.user_id).to be_nil
      expect(install.platform).to eq("android")
    end

    it "associates the current user server-side, ignoring any client user_id" do
      user = create(:user)
      other = create(:user)
      sign_in user

      post "/api/v1/app/installations/register",
           params: payload(user_id: other.id), as: :json

      expect(AppInstallation.find_by(installation_id: "inst-req-1").user_id).to eq(user.id)
    end

    it "is idempotent (second call updates, returns ok not created)" do
      post "/api/v1/app/installations/register", params: payload, as: :json
      post "/api/v1/app/installations/register", params: payload(app_version: "2.0.0"), as: :json

      expect(response).to have_http_status(:ok)
      expect(AppInstallation.where(installation_id: "inst-req-1").count).to eq(1)
      expect(AppInstallation.find_by(installation_id: "inst-req-1").app_version).to eq("2.0.0")
    end

    it "requires an installation_id" do
      post "/api/v1/app/installations/register", params: payload(installation_id: ""), as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "never persists when the flag is off (accepts silently)" do
      allow(AppInstallations::Register).to receive(:enabled?).and_return(false)
      post "/api/v1/app/installations/register", params: payload, as: :json
      expect(response).to have_http_status(:accepted)
      expect(AppInstallation.count).to eq(0)
    end
  end

  describe "PATCH /api/v1/app/installations/:installation_id" do
    it "updates permission/consent for an existing install" do
      create(:app_installation, installation_id: "inst-patch", push_enabled: false)

      patch "/api/v1/app/installations/inst-patch",
            params: { notification_permission: "denied", push_enabled: false }, as: :json

      expect(response).to have_http_status(:ok)
      install = AppInstallation.find_by(installation_id: "inst-patch")
      expect(install.notification_permission).to eq("denied")
    end
  end
end
