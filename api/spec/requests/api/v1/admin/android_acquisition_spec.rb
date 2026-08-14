require "rails_helper"

RSpec.describe "Api::V1::Admin::Analytics android acquisition", type: :request do
  ACQ_REQUEST_ENV = {
    "GOOGLE_ADS_DEVELOPER_TOKEN" => "dev-token",
    "GOOGLE_ADS_CLIENT_ID" => "client-id",
    "GOOGLE_ADS_CLIENT_SECRET" => "client-secret",
    "GOOGLE_ADS_REFRESH_TOKEN" => "refresh-token",
    "GOOGLE_ADS_CUSTOMER_ID_EASYHEALTH" => "1234567890",
    "GOOGLE_ADS_ANDROID_CAMPAIGN_ID" => "9911223344"
  }.freeze

  def no_credentials
    ACQ_REQUEST_ENV.keys.index_with(nil)
  end

  describe "GET /api/v1/admin/analytics/android_acquisition" do
    it "forbids non-admins" do
      sign_in create(:user)
      get "/api/v1/admin/analytics/android_acquisition"

      expect(response).to have_http_status(:forbidden)
    end

    it "returns both universes for an admin" do
      sign_in create(:user, :admin)
      with_env(ACQ_REQUEST_ENV) { get "/api/v1/admin/analytics/android_acquisition" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["ads"]).to be_present
      expect(body["easyhealth"]).to be_present
      expect(body["sync"]["status"]).to be_present
      expect(body["definitions"]["comparison_note"]).to include("complementares")
    end

    # The whole point of the cache: a page load must never depend on Google.
    it "does not call the Google Ads API" do
      sign_in create(:user, :admin)
      expect_any_instance_of(GoogleAds::Client).not_to receive(:search)

      with_env(ACQ_REQUEST_ENV) { get "/api/v1/admin/analytics/android_acquisition" }

      expect(response).to have_http_status(:ok)
    end

    it "keeps the Admin open when Google Ads is not configured" do
      sign_in create(:user, :admin)
      with_env(no_credentials) { get "/api/v1/admin/analytics/android_acquisition" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("sync", "status")).to eq("not_configured")
      expect(response.parsed_body["easyhealth"]).to be_present
    end

    it "rejects an invalid custom range with 422, not 500" do
      sign_in create(:user, :admin)
      with_env(ACQ_REQUEST_ENV) do
        get "/api/v1/admin/analytics/android_acquisition",
            params: { period: "custom", start: "2026-08-10", end: "2026-08-01" }
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end

    it "returns 503 only when the panel itself cannot be built" do
      sign_in create(:user, :admin)
      allow(Analytics::AndroidAcquisition).to receive(:new).and_raise(StandardError, "db down")

      get "/api/v1/admin/analytics/android_acquisition"

      expect(response).to have_http_status(:service_unavailable)
    end
  end
end
