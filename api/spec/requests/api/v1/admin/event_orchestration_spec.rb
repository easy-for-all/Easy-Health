require "rails_helper"

RSpec.describe "Api::V1::Admin::Analytics#event_orchestration", type: :request do
  let(:path) { "/api/v1/admin/analytics/event_orchestration" }

  it "refuses a non-admin" do
    sign_in create(:user)

    get path

    expect(response).to have_http_status(:forbidden)
  end

  it "refuses an anonymous request" do
    get path

    expect(response).not_to have_http_status(:ok)
  end

  # One request per example: the session established by sign_in only survives
  # the first request in this app, so looping requests inside one example would
  # test the session, not the endpoint.
  context "as an admin" do
    let(:admin) { create(:user, :admin, marketing_consent: true) }

    before { sign_in admin }

    it "returns the whole pipeline view" do
      UserEvent.create!(user: admin, event_name: "user_inactive_3_days", occurred_at: Time.current,
                        metadata: {}, make_delivery_status: "accepted_by_make", make_attempts_count: 1,
                        origin_surface: "backend_scheduler")

      get path

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to include(
        "period", "summary", "by_event", "candidate_channels",
        "push_dispatch_results", "by_origin", "schedulers", "recent_events", "warnings", "catalog"
      )
      expect(body.dig("summary", "accepted_by_make")).to eq(1)
      expect(body["by_origin"].find { |o| o["origin_surface"] == "backend_scheduler" }["events"]).to eq(1)
    end

    %w[24h 7d 30d].each do |period|
      it "accepts the #{period} period" do
        get path, params: { period: period }

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig("period", "key")).to eq(period)
      end
    end

    it "falls back to 24h for an unknown period instead of erroring" do
      get path, params: { period: "seculo" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("period", "key")).to eq("24h")
    end

    it "accepts a custom range" do
      get path, params: { from: "2026-08-01", to: "2026-08-10" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("period", "key")).to eq("custom")
    end

    it "rejects an invalid range without a 500" do
      get path, params: { from: "2026-08-10", to: "2026-08-01" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to be_present
    end

    it "reports the catalog as the source of truth" do
      get path

      expect(response.parsed_body.dig("catalog", "orchestration_events"))
        .to match_array(CommunicationEvents.orchestration_event_names)
    end

    it "answers 503 only when the panel itself breaks" do
      allow(::Analytics::EventOrchestration).to receive(:new).and_raise(StandardError, "boom")

      get path

      expect(response).to have_http_status(:service_unavailable)
      expect(response.parsed_body["error"]).to eq("Painel de eventos e comunicações indisponível no momento.")
    end
  end
end
