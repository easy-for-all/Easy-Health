require "rails_helper"

RSpec.describe "Api::V1::Admin stats", type: :request do
  describe "GET /api/v1/admin/stats" do
    it "forbids non-admins" do
      sign_in create(:user)
      get "/api/v1/admin/stats"
      expect(response).to have_http_status(:forbidden)
    end

    it "returns aggregated stats for an admin" do
      sign_in create(:user, :admin)
      get "/api/v1/admin/stats"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("total_users")
    end

    it "degrades to 503 when the schema is outdated (StatementInvalid)" do
      sign_in create(:user, :admin)
      allow(User).to receive(:reportable)
        .and_raise(ActiveRecord::StatementInvalid.new("PG::UndefinedColumn: column users.test_account does not exist"))

      get "/api/v1/admin/stats"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to include("migration pendente")
    end
  end
end
