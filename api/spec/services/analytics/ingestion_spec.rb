require "rails_helper"

RSpec.describe Analytics::Ingestion do
  let(:user) { create(:user) }

  def event(overrides = {})
    {
      event_name: "workout_completed",
      event_version: 1,
      occurred_at: Time.current.iso8601,
      anonymous_id: "anon-1",
      session_id: "sess-1",
      platform: "android",
      app_surface: "native_shell",
      environment: "test",
      properties: {}
    }.merge(overrides)
  end

  it "persists a known server-sink event with a server received_at" do
    expect {
      described_class.new(user: user, events: [ event ]).call
    }.to change(ProductAnalyticsEvent, :count).by(1)

    row = ProductAnalyticsEvent.last
    expect(row.event_name).to eq("workout_completed")
    expect(row.user_id).to eq(user.id)
    expect(row.platform).to eq("android")
    expect(row.received_at).to be_within(5.seconds).of(Time.current)
  end

  it "records analytics_event_rejected for an unknown event and does not persist it as-is" do
    result = described_class.new(user: user, events: [ event(event_name: "bogus_event") ]).call
    expect(result.rejected).to eq(1)
    expect(ProductAnalyticsEvent.where(event_name: "analytics_event_rejected")).to exist
    expect(ProductAnalyticsEvent.where(event_name: "bogus_event")).not_to exist
  end

  it "strips known sensitive keys from properties" do
    described_class.new(user: user, events: [ event(properties: { token: "secret", reps: 10 }) ]).call
    props = ProductAnalyticsEvent.where(event_name: "workout_completed").last.properties
    expect(props).not_to have_key("token")
    expect(props["reps"]).to eq(10)
  end

  it "allowlists auth_provider_clicked properties and preserves installation_id" do
    described_class.new(
      user: user,
      events: [
        event(
          event_name: "auth_provider_clicked",
          properties: {
            provider: "google",
            auth_screen: "sign_up",
            intent: "sign_up",
            terms_accepted: false,
            source: "auth_screen",
            installation_id: "install-123",
            email: "private@example.com",
            token: "secret",
            extra: "drop-me"
          }
        )
      ]
    ).call

    props = ProductAnalyticsEvent.where(event_name: "auth_provider_clicked").last.properties
    expect(props).to include(
      "provider" => "google",
      "auth_screen" => "sign_up",
      "intent" => "sign_up",
      "terms_accepted" => false,
      "source" => "auth_screen",
      "installation_id" => "install-123"
    )
    expect(props.keys).not_to include("email", "token", "extra")
  end

  it "drops terms_accepted from login auth_provider_clicked payloads" do
    described_class.new(
      user: user,
      events: [
        event(
          event_name: "auth_provider_clicked",
          properties: {
            provider: "email",
            auth_screen: "login",
            intent: "login",
            terms_accepted: false,
            source: "auth_screen"
          }
        )
      ]
    ).call

    props = ProductAnalyticsEvent.where(event_name: "auth_provider_clicked").last.properties
    expect(props).to include(
      "provider" => "email",
      "auth_screen" => "login",
      "intent" => "login",
      "source" => "auth_screen"
    )
    expect(props).not_to have_key("terms_accepted")
  end

  # auth_provider_clicked builds a NEW hash from an allow-list, so anything not
  # named there is dropped — including the attempt id, which is the only thing
  # tying this click to the failure or the success that followed it.
  it "keeps auth_attempt_id on auth_provider_clicked" do
    described_class.new(
      user: user,
      events: [
        event(
          event_name: "auth_provider_clicked",
          properties: {
            provider: "google", auth_screen: "login", intent: "login", source: "auth_screen",
            auth_attempt_id: "3f6c1d2e-9b0a-4c5d-8e7f-1a2b3c4d5e6f"
          }
        )
      ]
    ).call

    props = ProductAnalyticsEvent.where(event_name: "auth_provider_clicked").last.properties
    expect(props["auth_attempt_id"]).to eq("3f6c1d2e-9b0a-4c5d-8e7f-1a2b3c4d5e6f")
  end

  it "drops an attempt id that is not a bounded opaque identifier" do
    described_class.new(
      user: user,
      events: [
        event(
          event_name: "social_login_failed",
          properties: { failure_category: "user_cancelled", auth_attempt_id: "<script>alert(1)</script>" }
        )
      ]
    ).call

    props = ProductAnalyticsEvent.where(event_name: "social_login_failed").last.properties
    expect(props).not_to have_key("auth_attempt_id")
    expect(props["failure_category"]).to eq("user_cancelled")
  end

  # failure_category is a dimension the Admin groups and colours by. One stray
  # plugin string becoming a value is how a panel starts growing rows nobody
  # can group by, so anything outside the vocabulary is dropped.
  it "drops a failure_category outside the closed vocabulary" do
    described_class.new(
      user: user,
      events: [
        event(event_name: "auth_client_error", properties: { failure_category: "java.lang.Exception: boom" })
      ]
    ).call

    props = ProductAnalyticsEvent.where(event_name: "auth_client_error").last.properties
    expect(props).not_to have_key("failure_category")
  end

  it "does not let failure_category ride on an event that has no such contract" do
    described_class.new(
      user: user,
      events: [ event(event_name: "workout_completed", properties: { failure_category: "user_cancelled" }) ]
    ).call

    props = ProductAnalyticsEvent.where(event_name: "workout_completed").last.properties
    expect(props).not_to have_key("failure_category")
  end

  it "is idempotent on idempotency_key (no duplicate)" do
    key = "idem-123"
    described_class.new(user: user, events: [ event(idempotency_key: key) ]).call
    expect {
      described_class.new(user: user, events: [ event(idempotency_key: key) ]).call
    }.not_to change(ProductAnalyticsEvent, :count)
  end

  it "records the user's activation_platform on first event, and never overwrites it" do
    described_class.new(user: user, events: [ event(platform: "android") ]).call
    expect(user.reload.activation_platform).to eq("android")

    described_class.new(user: user, events: [ event(platform: "web") ]).call
    expect(user.reload.activation_platform).to eq("android")
  end

  it "accepts but does not persist a GA4-only event" do
    result = described_class.new(user: user, events: [ event(event_name: "home_viewed") ]).call
    expect(result.accepted).to eq(1)
    expect(ProductAnalyticsEvent.where(event_name: "home_viewed")).not_to exist
  end

  it "does nothing when ingestion is disabled" do
    allow(described_class).to receive(:enabled?).and_return(false)
    expect {
      described_class.new(user: user, events: [ event ]).call
    }.not_to change(ProductAnalyticsEvent, :count)
  end
end
