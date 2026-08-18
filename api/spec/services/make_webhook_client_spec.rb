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

  it "posts signed minimal payload and marks the event accepted by Make" do
    captured_request = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return("ok")
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
      expect(event.reload.make_delivery_status).to eq("accepted_by_make")
      expect(event.make_delivered_to_provider_at).to be_present
      expect(event.make_last_http_status).to eq(200)
      expect(event.make_delivery_channels).to eq(%w[push])
      expect(event.make_destination).to eq("push-progress")
      expect(captured_request["X-EasyHealth-Event-Id"]).to eq(event.id.to_s)
      expect(captured_request["X-EasyHealth-Idempotency-Key"]).to eq(event.idempotency_key)
      # Schema 2 is the canonical default now that no env override is set.
      expect(captured_request["X-EasyHealth-Schema-Version"]).to eq("2")
      expect(captured_request["X-EasyHealth-Signature"]).to be_present
      body = JSON.parse(captured_request.body)
      expect(body["schema_version"]).to eq(2)
      expect(body["idempotency_key"]).to eq(event.idempotency_key)
      expect(body.dig("delivery", "channels")).to eq(%w[push])
      expect(body.dig("user", "email")).to be_nil
    end
  end

  it "includes schema_version, timezone and locale so Make can schedule a push" do
    captured_request = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return("ok")
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
      expect(body["schema_version"]).to eq(2)
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
    allow(response).to receive(:body).and_return("ok")
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
      expect(body.dig("delivery", "channels")).to eq(%w[email])
      expect(body.dig("context", "plan_id")).to eq(plan.id)
      expect(body.dig("metadata", "trigger_source")).to eq("relationship_daily")
      expect(user_event.reload.payload_json["schema_version"]).to eq(2)
      expect(user_event.make_delivery_status).to eq("accepted_by_make")
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

  it "rebuilds an incomplete saved schema 2 snapshot before posting" do
    captured_body = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return("ok")
    http = instance_double(Net::HTTP)
    user_event = UserEvent.create!(
      user: user,
      event_name: "first_workout_completed",
      occurred_at: Time.current,
      source: "relationship_daily",
      metadata: { workout_session_id: 123 },
      make_delivery_status: "pending"
    )
    user_event.update!(
      payload_json: {
        "schema_version" => 2,
        "event_id" => user_event.id,
        "event_name" => user_event.event_name,
        "context" => {}
      }
    )

    with_env(make_env.merge("MAKE_EVENT_SCHEMA_VERSION" => "2")) do
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request) do |request|
        captured_body = request.body
        response
      end

      result = described_class.new.deliver(user_event)

      body = JSON.parse(captured_body)
      expect(result).to be_success
      expect(body.dig("context", "workout_session_id")).to eq(123)
      expect(body["idempotency_key"]).to eq(user_event.id.to_s)
      expect(user_event.reload.payload_json.dig("context", "workout_session_id")).to eq(123)
      expect(user_event.payload_json["idempotency_key"]).to eq(user_event.id.to_s)
    end
  end

  it "reuses the same idempotency key across retries" do
    captured = []
    response = Net::HTTPInternalServerError.new("1.1", "500", "Error")
    allow(response).to receive(:body).and_return("broken")
    http = instance_double(Net::HTTP)

    with_env(make_env) do
      event.update!(make_delivery_status: "pending")
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request) do |request|
        captured << {
          header: request["X-EasyHealth-Idempotency-Key"],
          payload: JSON.parse(request.body)["idempotency_key"]
        }
        response
      end

      described_class.new.deliver(event)
      described_class.new.deliver(event.reload)
    end

    expect(captured.size).to eq(2)
    expect(captured.map { |entry| entry[:header] }).to eq([ event.idempotency_key, event.idempotency_key ])
    expect(captured.map { |entry| entry[:payload] }).to eq([ event.idempotency_key, event.idempotency_key ])
    expect(UserEvent.where(id: event.id).count).to eq(1)
  end

  it "does not post an incomplete saved schema 2 snapshot when it cannot be rebuilt" do
    user_event = UserEvent.create!(
      user: user,
      event_name: "first_workout_completed",
      occurred_at: Time.current,
      source: "relationship_daily",
      metadata: {},
      make_delivery_status: "pending"
    )
    user_event.update!(
      payload_json: {
        "schema_version" => 2,
        "event_id" => user_event.id,
        "event_name" => user_event.event_name,
        "context" => {}
      }
    )

    with_env(make_env.merge("MAKE_EVENT_SCHEMA_VERSION" => "2")) do
      expect(Net::HTTP).not_to receive(:new)

      result = described_class.new.deliver(user_event)

      expect(result.status).to eq("retrying")
      expect(user_event.reload.make_delivery_status).to eq("retrying")
      expect(user_event.make_attempts_count).to eq(1)
      expect(user_event.make_last_error).to eq("missing_required_context")
      expect(user_event.make_last_http_status).to be_nil
    end
  end

  it "records a generic pre-POST exception without leaving the event sending" do
    client = described_class.new

    with_env(make_env) do
      event.update!(make_delivery_status: "pending")
      allow(client).to receive(:signature_for).and_raise(JSON::GeneratorError, "unexpected serialization failure")
      expect(Net::HTTP).not_to receive(:new)

      result = client.deliver(event)

      expect(result.status).to eq("retrying")
      expect(event.reload.make_delivery_status).to eq("retrying")
      expect(event.make_attempts_count).to eq(1)
      expect(event.make_last_error_class).to eq("JSON::GeneratorError")
      expect(event.make_last_error_message).to eq("unexpected serialization failure")
      expect(event.make_next_retry_at).to be_present
      expect(event.make_last_http_status).to be_nil
    end
  end

  describe "an orchestration event whose required context is missing" do
    # A configured communication event that cannot produce its payload is a
    # contract failure: it must fail loudly (not post), it must NOT be hidden as
    # "skipped", and it must not burn all five attempts on a deterministic bug.
    let(:incomplete_event) do
      UserEvent.create!(
        user: user,
        event_name: "first_workout_completed",
        occurred_at: Time.current,
        source: "relationship_daily",
        metadata: {},
        make_delivery_status: "pending"
      )
    end

    it "retries once, to cover the commit race" do
      with_env(make_env.merge("MAKE_EVENT_SCHEMA_VERSION" => "2")) do
        expect(Net::HTTP).not_to receive(:new)

        result = described_class.new.deliver(incomplete_event)

        expect(result.status).to eq("retrying")
        expect(incomplete_event.reload.make_delivery_status).to eq("retrying")
        expect(incomplete_event.make_last_error).to eq("missing_required_context")
        expect(incomplete_event.make_attempts_count).to eq(1)
        expect(incomplete_event.make_next_retry_at).to be_present
      end
    end

    it "dead-letters on the second attempt instead of skipping" do
      with_env(make_env.merge("MAKE_EVENT_SCHEMA_VERSION" => "2")) do
        described_class.new.deliver(incomplete_event)
        result = described_class.new.deliver(incomplete_event.reload)

        expect(result.status).to eq("dead_letter")
        expect(incomplete_event.reload.make_delivery_status).to eq("dead_letter")
        expect(incomplete_event.make_last_error).to eq("missing_required_context")
        expect(incomplete_event.make_last_error_class)
          .to eq("Make::EventPayloadSerializer::IncompleteEventError")
        expect(incomplete_event.make_next_retry_at).to be_nil
      end
    end

    it "never reports the failure as skipped" do
      with_env(make_env.merge("MAKE_EVENT_SCHEMA_VERSION" => "2")) do
        3.times { described_class.new.deliver(incomplete_event.reload) }

        expect(incomplete_event.reload.make_delivery_status).not_to eq("skipped")
        expect(incomplete_event.make_attempts_count).to be <= 3
      end
    end
  end

  # The client — not the serializer — is where "which channels do we expose"
  # gets answered, so the payload and make_delivery_channels can no longer
  # disagree. A user without email consent loses the EMAIL channel; the catalog
  # intent stays whole in candidate_channels.
  it "narrows the exposed channels to what routing decided, keeping candidate_channels whole" do
    no_email_consent = create(:user, marketing_consent: false)
    user_event = UserEvent.create!(
      user: no_email_consent,
      event_name: "user_inactive_7_days",
      occurred_at: Time.current,
      source: "relationship_daily",
      metadata: { last_workout_at: 8.days.ago.iso8601 },
      make_delivery_status: "pending"
    )
    captured_body = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return("ok")
    http = instance_double(Net::HTTP)

    with_env(make_env) do
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request) do |request|
        captured_body = request.body
        response
      end

      described_class.new.deliver(user_event)
    end

    body = JSON.parse(captured_body)
    expect(body.dig("delivery", "channels")).to eq(%w[push])
    expect(body.dig("delivery", "candidate_channels")).to match_array(%w[push email])
    expect(user_event.reload.make_delivery_channels_list).to eq(%w[push])
  end

  # An event with no catalog entry is not an orchestration event at all, so it
  # is rejected up front rather than reaching the communication check.
  it "disables an event that is not an orchestration event" do
    user_event = UserEvent.create!(
      user: user,
      event_name: "workout_created_not_started",
      occurred_at: Time.current,
      source: "relationship_daily",
      metadata: {},
      make_delivery_status: "pending"
    )

    with_env(make_env) do
      expect(Net::HTTP).not_to receive(:new)

      result = described_class.new.deliver(user_event)

      expect(result.status).to eq("disabled")
      expect(user_event.reload.make_delivery_status).to eq("disabled")
      expect(user_event.make_last_error).to eq("event_not_orchestration")
    end
  end

  # The legacy env allowlist can still force an uncatalogued event through
  # outside production (smoke tests). It then reaches the communication check,
  # which is what keeps it from being delivered as a real communication.
  it "skips a legacy env-only event that has no communication config" do
    user_event = UserEvent.create!(
      user: user,
      event_name: "workout_created_not_started",
      occurred_at: Time.current,
      source: "relationship_daily",
      metadata: {},
      make_delivery_status: "pending"
    )

    with_env(make_env.merge("MAKE_WEBHOOK_ALLOWED_EVENTS" => "workout_created_not_started")) do
      expect(Net::HTTP).not_to receive(:new)

      result = described_class.new.deliver(user_event)

      expect(result.status).to eq("skipped")
      expect(user_event.reload.make_delivery_status).to eq("skipped")
      expect(user_event.make_last_error).to eq("communication_event_disabled")
    end
  end

  it "marks the event retrying on HTTP errors while attempts remain" do
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

      expect(result.status).to eq("retrying")
      expect(event.reload.make_delivery_status).to eq("retrying")
      expect(event.make_last_http_status).to eq(500)
      expect(event.make_last_response_body).to eq("broken")
      expect(event.make_last_error_message).to eq("Make returned HTTP 500")
      expect(event.make_next_retry_at).to be_present
    end
  end

  it "marks the event accepted by Make on HTTP 202" do
    response = Net::HTTPAccepted.new("1.1", "202", "Accepted")
    allow(response).to receive(:body).and_return({ ok: true }.to_json)
    http = instance_double(Net::HTTP)

    with_env(make_env) do
      event.update!(make_delivery_status: "pending")
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(response)

      result = described_class.new.deliver(event)

      expect(result.status).to eq("accepted_by_make")
      expect(event.reload.make_delivery_status).to eq("accepted_by_make")
      expect(event.make_last_http_status).to eq(202)
    end
  end

  it "moves HTTP 400, 404, 422 and 500 to dead letter on the final attempt" do
    [
      [ Net::HTTPBadRequest, "400" ],
      [ Net::HTTPNotFound, "404" ],
      [ Net::HTTPUnprocessableEntity, "422" ],
      [ Net::HTTPInternalServerError, "500" ]
    ].each do |klass, code|
      user_event = event.dup
      user_event.idempotency_key = "final-http:#{klass.name.demodulize}"
      user_event.make_delivery_status = "pending"
      user_event.make_attempts_count = described_class::MAX_ATTEMPTS - 1
      user_event.save!
      response = klass.new("1.1", code, "Error")
      allow(response).to receive(:body).and_return("http error")
      http = instance_double(Net::HTTP)

      with_env(make_env) do
        allow(Net::HTTP).to receive(:new).and_return(http)
        allow(http).to receive(:use_ssl=)
        allow(http).to receive(:open_timeout=)
        allow(http).to receive(:read_timeout=)
        allow(http).to receive(:request).and_return(response)

        result = described_class.new.deliver(user_event)

        expect(result.status).to eq("dead_letter")
        expect(user_event.reload.make_delivery_status).to eq("dead_letter")
        expect(user_event.make_next_retry_at).to be_nil
      end
    end
  end

  it "records timeout class/message and keeps the event retryable" do
    http = instance_double(Net::HTTP)

    with_env(make_env) do
      event.update!(make_delivery_status: "pending")
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_raise(Net::ReadTimeout.new("execution expired"))

      result = described_class.new.deliver(event)

      expect(result.status).to eq("retrying")
      expect(event.reload.make_delivery_status).to eq("retrying")
      expect(event.make_last_error_class).to eq("Net::ReadTimeout")
      expect(event.make_last_error_message).to include("execution expired")
      expect(event.make_last_http_status).to be_nil
    end
  end

  it "records network exceptions as failed_to_reach_make on the final attempt" do
    http = instance_double(Net::HTTP)

    with_env(make_env) do
      event.update!(make_delivery_status: "pending", make_attempts_count: described_class::MAX_ATTEMPTS - 1)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_raise(Errno::ECONNREFUSED.new)

      result = described_class.new.deliver(event)

      expect(result.status).to eq("failed_to_reach_make")
      expect(event.reload.make_delivery_status).to eq("failed_to_reach_make")
      expect(event.make_attempts_count).to eq(described_class::MAX_ATTEMPTS)
      expect(event.make_next_retry_at).to be_nil
    end
  end

  it "truncates response bodies at 20 KB and redacts sensitive JSON keys" do
    secret_body = {
      token: "secret-token",
      data: "a" * (described_class::MAX_RESPONSE_BODY_BYTES + 200)
    }.to_json
    response = Net::HTTPInternalServerError.new("1.1", "500", "Error")
    allow(response).to receive(:body).and_return(secret_body)
    http = instance_double(Net::HTTP)

    with_env(make_env) do
      event.update!(make_delivery_status: "pending")
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(response)

      described_class.new.deliver(event)

      body = event.reload.make_last_response_body
      expect(body.bytesize).to be <= described_class::MAX_RESPONSE_BODY_BYTES
      expect(body).not_to include("secret-token")
    end
  end

  it "does not log webhook secrets or signatures in the structured delivery log" do
    response = Net::HTTPOK.new("1.1", "200", "OK")
    allow(response).to receive(:body).and_return("ok")
    http = instance_double(Net::HTTP)
    logs = []

    with_env(make_env.merge("MAKE_WEBHOOK_SECRET" => "super-secret")) do
      event.update!(make_delivery_status: "pending")
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(response)
      allow(Rails.logger).to receive(:info) { |message| logs << message.to_s }

      described_class.new.deliver(event)

      joined = logs.join("\n")
      expect(joined).to include("make_webhook_delivery")
      expect(joined).not_to include("super-secret")
      expect(joined).not_to include("X-EasyHealth-Signature")
    end
  end
end
