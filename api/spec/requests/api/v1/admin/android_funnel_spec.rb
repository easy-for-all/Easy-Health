require "rails_helper"

RSpec.describe "Api::V1::Admin::Analytics android funnel", type: :request do
  def install_with_events(build: "51", user: nil, events: [])
    record = create(:app_installation, app_build: build, user: user)
    events.each do |name|
      create(
        :product_analytics_event,
        event_name: name,
        occurred_at: 1.hour.ago,
        installation_id: record.installation_id
      )
    end
    record
  end

  describe "GET /api/v1/admin/analytics/android_funnel" do
    it "forbids non-admins" do
      sign_in create(:user)
      get "/api/v1/admin/analytics/android_funnel"

      expect(response).to have_http_status(:forbidden)
    end

    it "returns the funnel for an admin" do
      install_with_events(events: %w[app_first_open session_started landing_page_viewed])
      sign_in create(:user, :admin)

      get "/api/v1/admin/analytics/android_funnel"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      keys = body["steps"].map { |step| step["key"] }

      expect(keys).to eq(
        %w[installations first_open session_started entry_viewed auth_screen auth_choice
           auth_provider auth_client auth_api auth_done android_users linked]
      )
      expect(body["cohort"]["installations"]).to eq(1)
      expect(body["definitions"]["min_instrumented_build"]).to eq(51)
      expect(body["definitions"]["instrumentation_note"]).to include("build 51")
      expect(body["stage_buckets"].map { |bucket| bucket["key"] }).to start_with("no_events")
    end

    it "applies the period, build and audience filters" do
      install_with_events(build: "53", events: %w[app_first_open])
      install_with_events(
        user: create(:user, email: "robot@cloudtestlabaccounts.com"),
        events: %w[app_first_open]
      )
      sign_in create(:user, :admin)

      get "/api/v1/admin/analytics/android_funnel", params: { build: "53", audience: "all", period: "7d" }

      body = response.parsed_body
      expect(body["filters"]).to eq("period" => "7d", "build" => 53, "audience" => "all")
      expect(body["cohort"]["installations"]).to eq(1)
    end

    it "degrades to 503 instead of raising" do
      allow(::Analytics::AndroidFunnel).to receive(:new).and_raise(ActiveRecord::StatementInvalid)
      sign_in create(:user, :admin)

      get "/api/v1/admin/analytics/android_funnel"

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to be_present
    end
  end

  describe "GET /api/v1/admin/analytics/android_funnel/installations" do
    it "forbids non-admins" do
      sign_in create(:user)
      get "/api/v1/admin/analytics/android_funnel/installations", params: { stage: "stopped_entry_viewed" }

      expect(response).to have_http_status(:forbidden)
    end

    it "accepts stopped_session_started and lists the installations" do
      record = install_with_events(events: %w[app_first_open session_started])
      sign_in create(:user, :admin)

      get "/api/v1/admin/analytics/android_funnel/installations",
          params: { stage: "stopped_session_started" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["stage"]).to eq("stopped_session_started")
      expect(body["total"]).to eq(1)
      expect(body["installations"].first["installation_id"]).to eq(record.installation_id)
    end

    it "returns an empty list for an unknown stage" do
      sign_in create(:user, :admin)

      get "/api/v1/admin/analytics/android_funnel/installations", params: { stage: "whatever" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["installations"]).to eq([])
    end
  end
end
