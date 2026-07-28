require "rails_helper"

RSpec.describe "Api::V1::Admin::Analytics#android_installations", type: :request do
  it "returns the Android installed base for an admin" do
    sign_in create(:user, :admin)
    create(:app_installation, platform: "android", source: "register", app_build: "45")

    get "/api/v1/admin/analytics/android_installations"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["source"]).to eq("app_installations")
    expect(body["overview"]["total_installations"]).to eq(1)
    expect(body["reconciliation"]["link_rate"]).to include("value", "numerator", "denominator")
    expect(body["definitions"]["reconciliation_rate"])
      .to eq(::Analytics::AndroidInstallations::RECONCILIATION_RATE_DEFINITION)
    expect(body["definitions"]["linked_at_note"]).to include("fluxo novo")
    expect(body["data_quality"]).to include("missing_app_build")
    expect(body["operational_health"]).to be_an(Array)
    expect(body["google_play"]["configured"]).to be(false)
  end

  # End-to-end contract for the panel: the payload the admin UI renders must
  # carry the operational rate computed from user_id, and must keep the new-flow
  # figures beside it rather than as the definition of "linked". This is the
  # production sample that used to render as 50%.
  it "serves the operational reconciliation block for one new and one legacy link" do
    sign_in create(:user, :admin)
    create(:app_installation, platform: "android", user: create(:user),
                              first_authenticated_request_at: 2.hours.ago, linked_at: 2.hours.ago)
    create(:app_installation, platform: "android", user: create(:user),
                              first_authenticated_request_at: 2.hours.ago, linked_at: nil)

    get "/api/v1/admin/analytics/android_installations"

    reconciliation = response.parsed_body["reconciliation"]
    expect(reconciliation).to include(
      "observed_authenticated_installations" => 2,
      "linked_installations" => 2,
      "authenticated_unlinked_installations" => 0,
      "new_flow_linked_installations" => 1,
      "legacy_linked_observed_installations" => 1
    )
    expect(reconciliation["link_rate"]["value"]).to eq(100.0)

    health = response.parsed_body["operational_health"].find { |c| c["key"] == "reconciliation" }
    expect(health["status"]).to eq("ok")
  end

  it "works on an empty database" do
    sign_in create(:user, :admin)

    get "/api/v1/admin/analytics/android_installations"

    expect(response).to have_http_status(:ok)
    body = response.parsed_body
    expect(body["overview"]["total_installations"]).to eq(0)
    expect(body["overview"]["link_rate"]["value"]).to eq(0.0)
    expect(body["versions"]).to eq([])
  end

  # The aggregate is admin-wide: it must never carry a single identifiable row.
  it "never exposes installation ids or emails" do
    sign_in create(:user, :admin)
    user = create(:user, email: "leak@example.com")
    create(:app_installation, platform: "android", installation_id: "secret-install-id", user: user)

    get "/api/v1/admin/analytics/android_installations"

    expect(response.body).not_to include("secret-install-id")
    expect(response.body).not_to include("leak@example.com")
    expect(response.body).not_to include("installation_id")
    expect(response.body).not_to include("user_id")
  end

  it "returns 503 without leaking internals when the metrics fail" do
    sign_in create(:user, :admin)
    allow(::Analytics::AndroidInstallations).to receive(:new).and_raise(StandardError, "boom")

    get "/api/v1/admin/analytics/android_installations"

    expect(response).to have_http_status(:service_unavailable)
    expect(response.body).not_to include("boom")
  end

  it "forbids non-admins" do
    sign_in create(:user)
    get "/api/v1/admin/analytics/android_installations"
    expect(response).to have_http_status(:forbidden)
  end

  it "does not serve the metrics to an anonymous visitor" do
    get "/api/v1/admin/analytics/android_installations"
    expect(response).not_to have_http_status(:ok)
  end
end
