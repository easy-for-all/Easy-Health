require "rails_helper"

RSpec.describe "Api::V1::Admin::Analytics", type: :request do
  describe "GET /api/v1/admin/analytics/platform_comparison" do
    it "forbids non-admins" do
      sign_in create(:user)
      get "/api/v1/admin/analytics/platform_comparison"
      expect(response).to have_http_status(:forbidden)
    end

    it "returns cohort metrics for an admin" do
      sign_in create(:user, :admin)
      get "/api/v1/admin/analytics/platform_comparison"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["cohorts"]).to include("android", "web", "pwa")
      expect(body["note"]).to include("viés de seleção")
    end
  end
end
