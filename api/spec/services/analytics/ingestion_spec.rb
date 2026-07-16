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
