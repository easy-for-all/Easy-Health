require "rails_helper"

RSpec.describe RelationshipEventTracker do
  let(:user) { create(:user) }

  it "records internal events even when relationship communication is blocked" do
    user.update!(marketing_consent: false, unsubscribed_at: Time.current, email_bounced_at: Time.current)

    with_env(
      "MAKE_WEBHOOK_ENABLED" => "true",
      "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
      "MAKE_WEBHOOK_SECRET" => "secret",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => "first_workout_completed"
    ) do
      event = described_class.track(
        user: user,
        event_name: "first_workout_completed",
        metadata: { workout_session_id: 123 },
        idempotency_key: "first_workout_completed:test"
      )

      expect(event).to be_persisted
      expect(event.make_delivery_status).to eq("disabled")
    end
  end

  it "does not enqueue Make when allowed events is empty" do
    user.update!(marketing_consent: true)

    with_env(
      "MAKE_WEBHOOK_ENABLED" => "true",
      "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
      "MAKE_WEBHOOK_SECRET" => "secret",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => ""
    ) do
      event = described_class.track(
        user: user,
        event_name: "first_workout_completed",
        idempotency_key: "first_workout_completed:empty_allowed"
      )

      expect(event.make_delivery_status).to eq("disabled")
    end
  end

  it "creates one event per idempotency key" do
    2.times do
      described_class.track(
        user: user,
        event_name: "trial_day_3",
        idempotency_key: "trial_day_3:#{user.id}"
      )
    end

    expect(UserEvent.where(user: user, event_name: "trial_day_3", idempotency_key: "trial_day_3:#{user.id}").count).to eq(1)
  end

  it "removes sensitive metadata from internal payloads" do
    event = described_class.track(
      user: user,
      event_name: "workout_completed",
      metadata: {
        workout_session_id: 1,
        password: "nope",
        nested: { stripe_token: "nope", safe: "ok" }
      }
    )

    expect(event.metadata).to include("workout_session_id" => 1)
    expect(event.metadata).not_to have_key("password")
    expect(event.metadata["nested"]).to eq("safe" => "ok")
    expect(event.payload_json.dig("metadata", "nested")).to eq("safe" => "ok")
  end
end
