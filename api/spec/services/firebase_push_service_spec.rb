require "rails_helper"

# Unit spec for the FCM HTTP v1 sender. The network is always mocked here — the
# real Firebase round-trip is validated separately (see push:test:send_now and
# the device runbook), never with a mock.
RSpec.describe FirebasePushService do
  # A minimal stand-in for a Net::HTTPResponse (only #code and #body are read).
  FakeResponse = Struct.new(:code, :body)

  def stub_configured!
    allow(described_class).to receive(:configured?).and_return(true)
    allow(described_class).to receive(:project_id).and_return("easyhealth-test")
  end

  # Stub the transport at #post_message (private) so no credentials/network are
  # needed. Net::HTTP itself can't be any_instance-stubbed here because Sentry
  # prepends a module onto it. Captures the built payload for body assertions.
  def stub_transport(response)
    captured = {}
    allow_any_instance_of(described_class).to receive(:post_message) do |_svc, payload|
      captured[:payload] = payload
      response
    end
    captured
  end

  describe ".configured?" do
    it "is false when no service account is present" do
      with_env("FIREBASE_SERVICE_ACCOUNT_JSON" => nil, "FIREBASE_SERVICE_ACCOUNT_JSON_BASE64" => nil) do
        expect(described_class.configured?).to be(false)
      end
    end

    it "is true when service account JSON and project id resolve" do
      json = { "project_id" => "easyhealth-test", "client_email" => "x@y.iam" }.to_json
      with_env("FIREBASE_SERVICE_ACCOUNT_JSON" => json, "FIREBASE_PROJECT_ID" => nil) do
        expect(described_class.configured?).to be(true)
        expect(described_class.project_id).to eq("easyhealth-test")
      end
    end
  end

  describe "#deliver — message body" do
    it "sends notification + stringified data with the android channel and high priority" do
      stub_configured!
      captured = stub_transport(FakeResponse.new("200", { "name" => "projects/x/messages/1" }.to_json))

      described_class.new.deliver(
        token: "device-token-123456789",
        title: "Hi",
        body: "There",
        data: { type: "admin_push_test", n: 7 }
      )

      message = captured[:payload][:message]
      expect(message[:notification]).to eq(title: "Hi", body: "There")
      expect(message[:android]).to eq(priority: "high", notification: { channel_id: "workout_reminders" })
      # FCM requires all data values to be strings.
      expect(message[:data]).to eq(type: "admin_push_test", n: "7")
    end
  end

  describe "#deliver — response interpretation" do
    before { stub_configured! }

    it "returns sent with the provider message id on HTTP 200" do
      stub_transport(FakeResponse.new("200", { "name" => "projects/x/messages/42" }.to_json))
      result = described_class.new.deliver(token: "t", title: "a", body: "b")
      expect(result).to have_attributes(status: "sent", message_id: "projects/x/messages/42", invalid_token: false)
    end

    it "flags the token invalid on a definitive UNREGISTERED error" do
      body = { "error" => { "status" => "UNREGISTERED" } }.to_json
      stub_transport(FakeResponse.new("400", body))
      result = described_class.new.deliver(token: "t", title: "a", body: "b")
      expect(result).to have_attributes(status: "failed", error_code: "UNREGISTERED", invalid_token: true)
    end

    it "treats HTTP 404 as a dead token" do
      stub_transport(FakeResponse.new("404", "{}"))
      expect(described_class.new.deliver(token: "t", title: "a", body: "b").invalid_token).to be(true)
    end

    it "treats a 5xx as temporary (does NOT invalidate the token)" do
      stub_transport(FakeResponse.new("503", "service unavailable"))
      result = described_class.new.deliver(token: "t", title: "a", body: "b")
      expect(result).to have_attributes(status: "failed", invalid_token: false)
      expect(result.error_code).to eq("http_503")
    end

    it "returns a definitive missing_token result for a blank token" do
      result = described_class.new.deliver(token: "", title: "a", body: "b")
      expect(result).to have_attributes(status: "failed", error_code: "missing_token", invalid_token: true)
    end
  end

  describe "#deliver — not configured" do
    it "never hits the network and returns not_configured" do
      allow(described_class).to receive(:configured?).and_return(false)
      result = described_class.new.deliver(token: "t", title: "a", body: "b")
      expect(result).to have_attributes(status: "failed", error_code: "not_configured", invalid_token: false)
    end
  end

  describe "OAuth token caching" do
    it "builds the authorizer once and reuses the cached access token across calls" do
      described_class.reset_credentials!
      authorizer = instance_double("Signet::OAuth2::Client", access_token: "cached", expires_within?: false)
      allow(described_class).to receive(:build_authorizer).and_return(authorizer)

      expect(described_class.access_token).to eq("cached")
      expect(described_class.access_token).to eq("cached")
      expect(described_class).to have_received(:build_authorizer).once
    ensure
      described_class.reset_credentials!
    end
  end
end
