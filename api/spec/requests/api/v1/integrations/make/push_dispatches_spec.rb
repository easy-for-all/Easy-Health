require "rails_helper"

RSpec.describe "Api::V1::Integrations::Make::PushDispatches", type: :request do
  let(:dispatch_token) { "make-dispatch-secret" }
  let(:path) { "/api/v1/integrations/make/push_dispatches" }

  # Orchestration enabled + configured token for the whole file; individual
  # examples override as needed.
  around do |example|
    with_env(
      "MAKE_PUSH_ORCHESTRATION_ENABLED" => "true",
      "MAKE_PUSH_DISPATCH_TOKEN" => dispatch_token,
      "MAKE_PUSH_DISPATCH_TOKEN_CURRENT" => nil,
      "MAKE_PUSH_DISPATCH_TOKEN_PREVIOUS" => nil,
      "MAKE_PUSH_RATE_LIMIT_PER_USER" => "50"
    ) { example.run }
  end

  let(:user) do
    u = create(:user)
    u.notification_preferences!.update!(push_enabled: true, workout_reminders_enabled: true)
    u
  end

  before do
    allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(
      FirebasePushService::Result.new(status: "sent", message_id: "mock/1", invalid_token: false)
    )
  end

  def auth_headers(token = dispatch_token)
    { "Authorization" => "Bearer #{token}", "CONTENT_TYPE" => "application/json" }
  end

  def valid_payload(overrides = {})
    {
      event_id: "evt_#{SecureRandom.hex(4)}",
      user_id: user.id,
      notification_type: "workout_reminder",
      campaign_key: "workout_not_started_v1",
      title: "Seu treino está esperando",
      body: "Que tal começar agora?",
      route: "/workouts/456",
      data: { "workout_id" => "456" }
    }.merge(overrides)
  end

  def post_dispatch(payload, headers: auth_headers)
    post path, params: payload.to_json, headers: headers
  end

  describe "authentication" do
    it "rejects a request with no Authorization header" do
      post path, params: valid_payload.to_json, headers: { "CONTENT_TYPE" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a wrong token" do
      post_dispatch(valid_payload, headers: auth_headers("wrong-token"))
      expect(response).to have_http_status(:unauthorized)
    end

    it "accepts the PREVIOUS token during rotation" do
      create(:device_token, user: user)
      with_env("MAKE_PUSH_DISPATCH_TOKEN" => "new-token", "MAKE_PUSH_DISPATCH_TOKEN_PREVIOUS" => "old-token") do
        post_dispatch(valid_payload, headers: auth_headers("old-token"))
      end
      expect(response).to have_http_status(:ok)
      expect(json["status"]).to eq("provider_accepted")
    end
  end

  describe "feature flag off" do
    it "returns orchestration_disabled without sending" do
      expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
      with_env("MAKE_PUSH_ORCHESTRATION_ENABLED" => "false") do
        post_dispatch(valid_payload)
      end
      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "skipped", "reason" => "orchestration_disabled", "sent" => false)
    end
  end

  describe "payload validation" do
    it "rejects an unknown notification_type" do
      post_dispatch(valid_payload(notification_type: "spam"))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["reason"]).to eq("invalid_payload")
    end

    it "rejects a missing title" do
      post_dispatch(valid_payload(title: ""))
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects a route outside the allowlist" do
      post_dispatch(valid_payload(route: "https://evil.com"))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["detail"]).to eq("route_not_allowed")
    end

    it "rejects HTML/script in the title" do
      post_dispatch(valid_payload(title: "<script>alert(1)</script>"))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["detail"]).to eq("unsafe_content")
    end

    it "rejects a device token supplied by Make" do
      post_dispatch(valid_payload(token: "should-not-be-here"))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["detail"]).to eq("forbidden_token_field")
    end

    it "rejects a token nested inside data" do
      post_dispatch(valid_payload(data: { "device_token" => "sneaky" }))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["detail"]).to eq("forbidden_token_field")
    end

    it "rejects an oversized body" do
      post_dispatch(valid_payload(data: { "x" => "a" * 9000 }))
      expect(response).to have_http_status(:payload_too_large)
    end
  end

  describe "user resolution & preferences" do
    it "returns a neutral skip for a non-existent user" do
      post_dispatch(valid_payload(user_id: 0))
      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "skipped", "reason" => "user_not_found", "sent" => false)
    end

    it "skips global opt-out" do
      user.notification_preferences.update!(push_enabled: false)
      create(:device_token, user: user)
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("global_opt_out")
    end

    it "skips category opt-out (reminders disabled)" do
      user.notification_preferences.update!(workout_reminders_enabled: false)
      create(:device_token, user: user)
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("category_opt_out")
    end

    it "skips when the user has no active token" do
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("no_active_token")
    end

    it "skips an invalidated token as no_active_token" do
      create(:device_token, user: user).invalidate!("test")
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("no_active_token")
    end

    it "skips permission_denied when the only token was denied" do
      create(:device_token, user: user, permission_status: "denied")
      post_dispatch(valid_payload)
      expect(json["reason"]).to eq("permission_denied")
    end
  end

  describe "successful dispatch" do
    before { create(:device_token, user: user) }

    it "sends and records a provider_accepted dispatch" do
      post_dispatch(valid_payload)

      expect(response).to have_http_status(:ok)
      expect(json).to include("status" => "provider_accepted", "sent" => true,
                              "tokens_attempted" => 1, "tokens_accepted" => 1)
      dispatch = PushDispatch.last
      expect(dispatch.status).to eq("provider_accepted")
      expect(dispatch.provider_accepted_at).to be_present
    end

    it "builds FCM data with a single source key and reserved keys winning over Make data" do
      captured = nil
      allow_any_instance_of(FirebasePushService).to receive(:deliver) do |_svc, **kwargs|
        captured = kwargs[:data]
        FirebasePushService::Result.new(status: "sent", message_id: "m", invalid_token: false)
      end

      # Make sends its own workout_id AND tries to override "source".
      post_dispatch(valid_payload(data: { "workout_id" => "456", "source" => "make_scenario" }))

      serialized = JSON.parse(captured.to_json)
      # The duplicate-key bug (:source vs "source") would surface here.
      expect(serialized.keys.count { |k| k == "source" }).to eq(1)
      expect(serialized["source"]).to eq("make")            # reserved key wins
      expect(serialized["target_path"]).to eq("/workouts/456")
      expect(serialized["workout_id"]).to eq("456")         # Make data passes through
    end

    it "never persists a device token in payload_json" do
      post_dispatch(valid_payload(data: { "workout_id" => "456" }))
      expect(PushDispatch.last.payload_json.to_json).not_to include(DeviceToken.last.token)
    end

    it "is idempotent: the same event returns duplicate without re-sending" do
      payload = valid_payload
      post_dispatch(payload)
      expect(json["status"]).to eq("provider_accepted")

      expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
      post_dispatch(payload)
      expect(json).to include("status" => "duplicate", "sent" => false)
      expect(PushDispatch.count).to eq(1)
    end

    it "returns 502 with the Firebase message and does NOT invalidate on INVALID_ARGUMENT" do
      device = user.device_tokens.first
      allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(
        FirebasePushService::Result.new(
          status: "failed", error_code: "INVALID_ARGUMENT",
          error_message: "The registration token is not a valid FCM registration token",
          invalid_token: false
        )
      )
      post_dispatch(valid_payload)

      expect(response).to have_http_status(:bad_gateway)
      expect(json).to include("status" => "failed", "sent" => false,
                              "last_error_code" => "INVALID_ARGUMENT")
      expect(json["last_error_message"]).to match(/registration token/)
      expect(device.reload.enabled).to be(true)
      expect(PushDispatch.last.last_error_message).to be_present
    end

    it "delivers to a second device when the first is rejected" do
      create(:device_token, user: user)
      allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(
        FirebasePushService::Result.new(status: "failed", error_code: "http_500", invalid_token: false),
        FirebasePushService::Result.new(status: "sent", message_id: "mock/2", invalid_token: false)
      )
      post_dispatch(valid_payload)
      expect(json["status"]).to eq("partially_accepted")
      expect(json["tokens_rejected"]).to eq(1)
      expect(json["tokens_accepted"]).to eq(1)
    end
  end

  describe "rate limiting" do
    before { create(:device_token, user: user) }

    it "returns rate_limited over the per-user threshold" do
      with_env("MAKE_PUSH_RATE_LIMIT_PER_USER" => "1") do
        PushDispatch.create!(user: user, notification_type: "workout_reminder",
                             idempotency_key: "seed:#{SecureRandom.hex(4)}", status: "provider_accepted")
        post_dispatch(valid_payload)
      end
      expect(response).to have_http_status(:too_many_requests)
      expect(json["reason"]).to eq("rate_limited")
    end
  end

  def json
    JSON.parse(response.body)
  end
end
