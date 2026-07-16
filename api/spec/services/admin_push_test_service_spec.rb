require "rails_helper"

RSpec.describe AdminPushTestService do
  let(:admin) { create(:user, :admin) }

  def sent_result
    FirebasePushService::Result.new(status: "sent", message_id: "m/1", invalid_token: false)
  end

  before { allow(FirebasePushService).to receive(:configured?).and_return(true) }

  it "refuses a non-admin user" do
    result = described_class.new(create(:user)).call
    expect(result).to have_attributes(ok: false, error: "not_admin")
  end

  it "reports no_active_device when the admin has no token" do
    expect(described_class.new(admin).call).to have_attributes(ok: false, error: "no_active_device")
  end

  it "reports not_configured when Firebase is unavailable" do
    allow(FirebasePushService).to receive(:configured?).and_return(false)
    admin.device_tokens.create!(token: "t", platform: "android")
    expect(described_class.new(admin).call).to have_attributes(ok: false, error: "not_configured")
  end

  it "sends, records an audit + provider event, and invalidates a dead token" do
    admin.device_tokens.create!(token: "dead-token", platform: "android")
    dead = FirebasePushService::Result.new(status: "failed", error_code: "UNREGISTERED", invalid_token: true)
    allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(dead)

    result = described_class.new(admin).call

    expect(result.ok).to be(false) # rejected by FCM
    expect(admin.device_tokens.first.reload.enabled).to be(false)
    expect(UserEvent.where(user_id: admin.id, event_name: "admin_push_test_requested")).to be_present
    expect(UserEvent.where(user_id: admin.id, event_name: "push_provider_rejected")).to be_present
  end

  describe "rate limiting" do
    # Test env uses a null_store; swap in a real memory store so the cooldown
    # actually persists between the two calls. Safe here (no Warden/session).
    around do |example|
      original = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      example.run
    ensure
      Rails.cache = original
    end

    it "blocks a second send within the cooldown window" do
      admin.device_tokens.create!(token: "tok", platform: "android")
      allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(sent_result)

      expect(described_class.new(admin).call.ok).to be(true)
      expect(described_class.new(admin).call).to have_attributes(ok: false, error: "rate_limited")
    end
  end
end
