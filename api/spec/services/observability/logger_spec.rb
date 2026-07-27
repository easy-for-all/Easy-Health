require "rails_helper"

RSpec.describe Observability::Logger do
  after { Observability::Context.reset }

  def capture(&block)
    described_class.collect(&block)
  end

  it "emits one payload per event with the canonical envelope" do
    payloads = capture { described_class.emit("http_request_completed", status: 200, duration_ms: 12.5) }

    expect(payloads.size).to eq(1)
    payload = payloads.first
    expect(payload[:event]).to eq("http_request_completed")
    expect(payload[:service]).to eq("easyhealth-api")
    expect(payload[:level]).to eq("info")
    expect(payload[:status]).to eq(200)
    expect(payload[:ts]).to be_present
  end

  it "derives status_class from status" do
    expect(capture { described_class.emit("e", status: 200) }.first[:status_class]).to eq("2xx")
    expect(capture { described_class.emit("e", status: 404) }.first[:status_class]).to eq("4xx")
    expect(capture { described_class.emit("e", status: 503) }.first[:status_class]).to eq("5xx")
  end

  it "inherits the correlation context" do
    Observability::Context.request_id = "req-1"
    Observability::Context.platform = "android"
    Observability::Context.app_build = "51"

    payload = capture { described_class.emit("some_event") }.first

    expect(payload[:request_id]).to eq("req-1")
    expect(payload[:platform]).to eq("android")
    expect(payload[:build_group]).to eq("current")
  end

  it "drops nil fields so lines stay small" do
    payload = capture { described_class.emit("some_event") }.first

    expect(payload).not_to have_key(:user_ref)
    expect(payload).not_to have_key(:job_key)
  end

  it "serializes to valid JSON" do
    payload = capture { described_class.emit("some_event", metadata: { a: 1 }) }.first

    expect { JSON.parse(payload.to_json) }.not_to raise_error
  end

  describe "privacy" do
    it "strips sensitive keys from metadata via the shared sanitizer" do
      payload = capture do
        described_class.emit("google_auth_failed", metadata: {
          email: "someone@example.com",
          id_token: "ya29.super-secret",
          auth_flow: "native"
        })
      end.first

      serialized = payload.to_json
      expect(serialized).not_to include("someone@example.com")
      expect(serialized).not_to include("ya29.super-secret")
      expect(payload[:metadata]["auth_flow"]).to eq("native")
    end

    it "never leaks a raw installation id, only the hashed ref" do
      Observability::Context.installation_id = "install-raw-value"

      payload = capture { described_class.emit("some_event") }.first

      expect(payload.to_json).not_to include("install-raw-value")
      expect(payload[:installation_ref]).to start_with("ins_")
    end

    it "replaces oversized metadata instead of emitting it" do
      payload = capture do
        described_class.emit("some_event", metadata: { blob: "x" * 5_000 })
      end.first

      expect(payload[:metadata]).to eq({ truncated: true })
    end

    it "caps nesting depth" do
      deep = { a: { b: { c: { d: { e: "too deep" } } } } }
      payload = capture { described_class.emit("some_event", metadata: deep) }.first

      expect(payload[:metadata].to_json).not_to include("too deep")
    end
  end

  it "never raises out to the caller" do
    allow(Observability::Context).to receive(:to_log_context).and_raise(StandardError)

    expect { described_class.emit("some_event") }.not_to raise_error
  end
end
