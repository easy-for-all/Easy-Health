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
      expect(captured_request["X-EasyHealth-Signature"]).to be_present
      expect(JSON.parse(captured_request.body).dig("user", "email")).to be_nil
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
