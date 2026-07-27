require "rails_helper"

RSpec.describe "Observability request context", type: :request do
  let(:user) { create(:user) }

  def emitted(event)
    @payloads.select { |p| p[:event] == event }
  end

  around do |example|
    Observability::Logger.collect do |payloads|
      @payloads = payloads
      example.run
    end
  end

  it "is inserted immediately after ActionDispatch::RequestId" do
    stack = Rails.application.middleware.map { |m| m.name }
    expect(stack[stack.index("ActionDispatch::RequestId") + 1]).to eq("ObservabilityRequestContext")
  end

  it "echoes X-Request-Id on the response" do
    sign_in user
    get "/api/v1/auth/me"

    expect(response.headers["X-Request-Id"]).to be_present
  end

  it "emits exactly one http_request_completed per request" do
    sign_in user
    get "/api/v1/auth/me"

    expect(emitted("http_request_completed").size).to eq(1)
  end

  it "captures the correlation headers into the log line" do
    sign_in user
    get "/api/v1/auth/me", headers: {
      "X-Installation-Id" => "install-abc",
      "X-Platform" => "android",
      "X-App-Version" => "1.0.51",
      "X-App-Build" => "51",
      "X-Session-Id" => "session-abc"
    }

    payload = emitted("http_request_completed").first
    expect(payload[:platform]).to eq("android")
    expect(payload[:app_version]).to eq("1.0.51")
    expect(payload[:build_group]).to eq("current")
    expect(payload[:route]).to eq("/api/v1/auth/me")
    expect(payload[:status]).to eq(200)
    expect(payload[:duration_ms]).to be_a(Numeric)
  end

  it "hashes the identifiers instead of logging them" do
    sign_in user
    get "/api/v1/auth/me", headers: { "X-Installation-Id" => "install-abc", "X-Session-Id" => "session-abc" }

    payload = emitted("http_request_completed").first
    expect(payload.to_json).not_to include("install-abc")
    expect(payload.to_json).not_to include("session-abc")
    expect(payload[:installation_ref]).to start_with("ins_")
    expect(payload[:session_ref]).to start_with("ses_")
  end

  it "resolves the signed-in user without any controller change" do
    sign_in user
    get "/api/v1/auth/me"

    expect(emitted("http_request_completed").first[:user_ref]).to eq("u_#{user.id}")
  end

  it "drops a malformed header rather than passing it through" do
    sign_in user
    get "/api/v1/auth/me", headers: { "X-Platform" => "<script>", "X-App-Build" => "not-a-build" }

    payload = emitted("http_request_completed").first
    expect(payload[:app_build]).to be_nil
    expect(payload.to_json).not_to include("script")
  end

  it "collapses an unrouted path into a single label instead of a new dimension" do
    get "/definitely/not/a/route/#{SecureRandom.hex(8)}"

    expect(emitted("http_request_completed").first[:route]).to eq("unmatched")
  end

  it "skips the health check path" do
    get "/up"

    expect(emitted("http_request_completed")).to be_empty
  end

  it "does not resolve the context for an anonymous caller" do
    get "/api/v1/auth/me"

    expect(emitted("http_request_completed").first[:user_ref]).to be_nil
  end

  it "never breaks a request when the observability layer raises" do
    allow(Observability::HttpStats).to receive(:record).and_raise(StandardError, "boom")
    sign_in user

    get "/api/v1/auth/me"

    expect(response).to have_http_status(:ok)
  end

  it "resets the context between requests" do
    sign_in user
    get "/api/v1/auth/me", headers: { "X-Installation-Id" => "install-abc" }

    expect(Observability::Context.installation_id).to be_nil
  end
end
