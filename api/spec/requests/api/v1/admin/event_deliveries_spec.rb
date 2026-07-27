require "rails_helper"

RSpec.describe "Api::V1::Admin event deliveries", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user, name: "Ana Souza", email: "ana@example.com") }

  def create_delivery(overrides = {})
    UserEvent.create!(
      {
        user: user,
        event_name: "first_workout_completed",
        occurred_at: Time.current,
        source: "spec",
        make_delivery_status: "accepted_by_make",
        make_attempts_count: 2,
        make_first_attempt_at: 5.minutes.ago,
        make_last_attempt_at: 4.minutes.ago,
        make_delivered_to_provider_at: 4.minutes.ago,
        make_last_http_status: 202,
        make_last_response_body: "{\"ok\":true}",
        make_processing_status: "routed",
        make_processing_message: "Rota de push executada",
        make_execution_id: "exec-123",
        make_delivery_channels: %w[push],
        make_destination: "push-progress",
        payload_json: {
          event_id: 1,
          event_name: "first_workout_completed",
          delivery: { channels: %w[push] }
        },
        metadata: { "workout_session_id" => 88 },
        idempotency_key: "first_workout_completed:#{user.id}:88"
      }.merge(overrides)
    )
  end

  describe "GET /api/v1/admin/analytics/event_deliveries" do
    it "forbids non-admins" do
      sign_in create(:user)
      get "/api/v1/admin/analytics/event_deliveries"
      expect(response).to have_http_status(:forbidden)
    end

    it "filters deliveries and returns a summary for admins" do
      matching = create_delivery
      create_delivery(
        event_name: "user_inactive_3_days",
        make_delivery_status: "retrying",
        make_last_http_status: 500,
        make_processing_status: "unknown",
        make_delivery_channels: %w[email],
        make_destination: "email-retention",
        idempotency_key: "user_inactive_3_days:#{user.id}"
      )

      sign_in admin
      get "/api/v1/admin/analytics/event_deliveries", params: {
        period: "24h",
        event_name: "first_workout",
        user: "ana@example.com",
        channel: "push",
        destination: "push-progress",
        delivery_status: "accepted_by_make",
        http_status: "202",
        make_status: "routed"
      }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["summary"]).to include(
        "events_generated" => 1,
        "accepted_by_make" => 1,
        "with_error" => 0,
        "pending_or_retry" => 0
      )
      expect(body["deliveries"].size).to eq(1)
      expect(body["deliveries"].first).to include(
        "id" => matching.id,
        "event_name" => "first_workout_completed",
        "delivery_status" => "accepted_by_make",
        "attempt_count" => 2,
        "http_status" => 202,
        "make_status" => "routed",
        "destination" => "push-progress"
      )
      expect(body["deliveries"].first.dig("user", "email")).to eq("ana@example.com")
    end
  end

  describe "GET /api/v1/admin/analytics/event_deliveries/:id" do
    it "returns payload, response and error fields for an admin" do
      delivery = create_delivery(make_last_error_message: "previous error")

      sign_in admin
      get "/api/v1/admin/analytics/event_deliveries/#{delivery.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body.fetch("delivery")
      expect(body["id"]).to eq(delivery.id)
      expect(body["payload"]).to include("event_name" => "first_workout_completed")
      expect(body["response_body"]).to eq("{\"ok\":true}")
      expect(body["error_message"]).to eq("previous error")
      expect(body["idempotency_key"]).to eq("first_workout_completed:#{user.id}:88")
      expect(body["make_execution_id"]).to eq("exec-123")
    end
  end
end
