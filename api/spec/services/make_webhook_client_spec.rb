require "rails_helper"

RSpec.describe MakeWebhookClient do
  let(:user) { create(:user, marketing_consent: true) }
  let(:event) do
    RelationshipEventTracker.track(
      user: user,
      event_name: "first_workout_completed",
      metadata: { workout_session_id: 10 },
      idempotency_key: "first_workout_completed:make_client",
      suppress_make_delivery: true
    )
  end

  def make_env
    {
      "MAKE_WEBHOOK_ENABLED" => "true",
      "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
      "MAKE_WEBHOOK_SECRET" => "secret",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => "first_workout_completed",
      "MAKE_WEBHOOK_PAYLOAD_MODE" => "minimal"
    }
  end

  it "posts signed minimal payload and marks the event delivered" do
    captured_request = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    http = instance_double(Net::HTTP)

    with_env(make_env) do
      event.update!(make_delivery_status: "pending")
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request) do |request|
        captured_request = request
        response
      end

      result = described_class.new.deliver(event)

      expect(result).to be_success
      expect(event.reload.make_delivery_status).to eq("delivered")
      expect(captured_request["X-EasyHealth-Event-Id"]).to eq(event.id.to_s)
      expect(captured_request["X-EasyHealth-Schema-Version"]).to eq("1")
      expect(captured_request["X-EasyHealth-Signature"]).to be_present
      expect(JSON.parse(captured_request.body).dig("user", "email")).to be_nil
    end
  end

  it "includes schema_version, timezone and locale so Make can schedule a push" do
    captured_request = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    http = instance_double(Net::HTTP)
    user.update!(time_zone: "America/Sao_Paulo")

    with_env(make_env) do
      event.update!(make_delivery_status: "pending")
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request) do |request|
        captured_request = request
        response
      end

      described_class.new.deliver(event)

      body = JSON.parse(captured_request.body)
      expect(body["schema_version"]).to eq(1)
      expect(body.dig("user", "timezone")).to eq("America/Sao_Paulo")
      expect(body.dig("user", "locale")).to eq("pt-BR")
      # Still no sensitive PII in minimal mode, and never a device token.
      expect(body.dig("user", "email")).to be_nil
      expect(captured_request.body).not_to match(/fcm|device_token|"token"/i)
    end
  end

  it "posts schema version 2 payload with delivery channels and context" do
    captured_request = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    http = instance_double(Net::HTTP)
    plan = user.workout_plans.create!(active: true, created_at: 70.minutes.ago)
    user_event = UserEvent.create!(
      user: user,
      event_name: "first_workout_created",
      occurred_at: Time.current,
      source: "relationship_daily",
      metadata: { workout_plan_id: plan.id },
      make_delivery_status: "pending"
    )

    with_env(make_env.merge(
      "MAKE_EVENT_SCHEMA_VERSION" => "2",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => "first_workout_created"
    )) do
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request) do |request|
        captured_request = request
        response
      end

      result = described_class.new.deliver(user_event)

      body = JSON.parse(captured_request.body)
      expect(result).to be_success
      expect(captured_request["X-EasyHealth-Schema-Version"]).to eq("2")
      expect(body["schema_version"]).to eq(2)
      expect(body.dig("delivery", "channels")).to eq(%w[email push])
      expect(body.dig("context", "plan_id")).to eq(plan.id)
      expect(body.dig("metadata", "trigger_source")).to eq("relationship_daily")
      expect(user_event.reload.payload_json["schema_version"]).to eq(2)
    end
  end

  it "reuses the saved payload snapshot for retries" do
    captured_bodies = []
    response = Net::HTTPInternalServerError.new("1.1", "500", "Error")
    allow(response).to receive(:body).and_return("broken")
    http = instance_double(Net::HTTP)
    plan = user.workout_plans.create!(active: true, created_at: 70.minutes.ago)
    user_event = UserEvent.create!(
      user: user,
      event_name: "first_workout_created",
      occurred_at: Time.current,
      source: "relationship_daily",
      metadata: { workout_plan_id: plan.id },
      make_delivery_status: "pending"
    )

    with_env(make_env.merge(
      "MAKE_EVENT_SCHEMA_VERSION" => "2",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => "first_workout_created"
    )) do
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request) do |request|
        captured_bodies << request.body
        response
      end

      described_class.new.deliver(user_event)
      ENV["MAKE_EVENT_SCHEMA_VERSION"] = "1"
      described_class.new.deliver(user_event)

      expect(captured_bodies.size).to eq(2)
      expect(captured_bodies.first).to eq(captured_bodies.second)
      expect(JSON.parse(captured_bodies.second)["schema_version"]).to eq(2)
    end
  end

  it "marks an incoherent schema version 2 event failed without posting" do
    user_event = UserEvent.create!(
      user: user,
      event_name: "workout_created_not_started",
      occurred_at: Time.current,
      source: "relationship_daily",
      metadata: {},
      make_delivery_status: "pending"
    )

    with_env(make_env.merge(
      "MAKE_EVENT_SCHEMA_VERSION" => "2",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => "workout_created_not_started"
    )) do
      expect(Net::HTTP).not_to receive(:new)

      result = described_class.new.deliver(user_event)

      expect(result.status).to eq("failed")
      expect(user_event.reload.make_delivery_status).to eq("failed")
      expect(user_event.make_last_error).to include("missing_required_context")
      expect(user_event.make_attempts_count).to eq(1)
    end
  end

  it "marks the event failed on HTTP errors" do
    response = Net::HTTPInternalServerError.new("1.1", "500", "Error")
    allow(response).to receive(:body).and_return("broken")
    http = instance_double(Net::HTTP)

    with_env(make_env) do
      event.update!(make_delivery_status: "pending")
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(response)

      result = described_class.new.deliver(event)

      expect(result.status).to eq("failed")
      expect(event.reload.make_delivery_status).to eq("failed")
      expect(event.make_last_error).to include("HTTP 500")
    end
  end
end
