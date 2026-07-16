require "rails_helper"

RSpec.describe "Api::V1::Analytics::Events", type: :request do
  def valid_event(overrides = {})
    {
      event_name: "workout_started",
      event_version: 1,
      occurred_at: Time.current.iso8601,
      anonymous_id: "anon-req-1",
      session_id: "sess-req-1",
      platform: "web",
      app_surface: "desktop_web",
      environment: "test",
      properties: {}
    }.merge(overrides)
  end

  it "accepts a batch from an anonymous (unauthenticated) client" do
    post "/api/v1/analytics/events", params: { events: [ valid_event ] }, as: :json

    expect(response).to have_http_status(:accepted)
    row = ProductAnalyticsEvent.last
    expect(row.event_name).to eq("workout_started")
    expect(row.user_id).to be_nil
    expect(row.anonymous_id).to eq("anon-req-1")
  end

  it "associates the current user server-side, ignoring any client user_id" do
    user = create(:user)
    other = create(:user)
    sign_in user

    post "/api/v1/analytics/events",
         params: { events: [ valid_event(user_id: other.id) ] }, as: :json

    expect(ProductAnalyticsEvent.last.user_id).to eq(user.id)
  end

  it "rejects an oversized batch" do
    events = Array.new(Analytics::Ingestion::MAX_BATCH_SIZE + 5) { valid_event }
    post "/api/v1/analytics/events", params: { events: events }, as: :json
    expect(response).to have_http_status(:content_too_large)
  end

  it "returns 400 when events are missing" do
    post "/api/v1/analytics/events", params: {}, as: :json
    expect(response).to have_http_status(:bad_request)
  end
end
