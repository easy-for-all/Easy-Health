require "rails_helper"

RSpec.describe "Api::V1::Admin::Analytics#android_installations", type: :request do
  it "returns the Android installed base for an admin" do
    admin = create(:user, :admin)
    sign_in admin
    create(:app_installation, platform: "android", source: "register")

    get "/api/v1/admin/analytics/android_installations"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["source"]).to eq("app_installations")
    expect(body["installations"]["known"]).to eq(1)
    expect(body["tracking_coverage"]).to include("numerator", "denominator")
    expect(body["funnel"]).to be_an(Array)
  end

  it "forbids non-admins" do
    sign_in create(:user)
    get "/api/v1/admin/analytics/android_installations"
    expect(response).to have_http_status(:forbidden)
  end
end
