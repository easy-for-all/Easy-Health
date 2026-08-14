require "rails_helper"

RSpec.describe RelationshipEventTracker do
  let(:user) { create(:user) }

  let(:make_env) do
    {
      "MAKE_WEBHOOK_ENABLED" => "true",
      "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
      "MAKE_WEBHOOK_SECRET" => "secret",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => ""
    }
  end

  # Hard gates are per channel. Email consent must not decide the fate of a
  # push-only event: whether that push can be sent is answered at dispatch time.
  it "still delivers a push-only event for a user with no email consent" do
    user.update!(marketing_consent: false, unsubscribed_at: Time.current, email_bounced_at: Time.current)

    with_env(make_env) do
      event = described_class.track(
        user: user,
        event_name: "first_workout_completed",
        metadata: { workout_session_id: 123 },
        idempotency_key: "first_workout_completed:test"
      )

      expect(event).to be_persisted
      expect(event.make_delivery_status).to eq("pending")
      expect(event.make_delivery_channels_list).to eq(%w[push])
    end
  end

  it "keeps the email channel closed for a user with no email consent" do
    user.update!(marketing_consent: false)

    with_env(make_env) do
      event = described_class.track(
        user: user,
        event_name: "user_created",
        idempotency_key: "user_created:no_consent"
      )

      expect(event).to be_persisted
      expect(event.make_delivery_status).to eq("disabled")
      expect(event.make_last_error).to eq("no_deliverable_channel")
    end
  end

  # user_inactive_7_days is push+email. Losing email consent must narrow the
  # candidate channels, never suppress the event.
  it "narrows a multichannel event to the channels the user still allows" do
    user.update!(marketing_consent: false)

    with_env(make_env) do
      event = described_class.track(
        user: user,
        event_name: "user_inactive_7_days",
        metadata: { last_workout_at: 8.days.ago.iso8601 },
        idempotency_key: "user_inactive_7_days:narrow"
      )

      expect(event.make_delivery_status).to eq("pending")
      expect(event.make_delivery_channels_list).to eq(%w[push])
    end
  end

  # Regression guard: an empty MAKE_WEBHOOK_ALLOWED_EVENTS used to mean "send
  # nothing", which silently disabled every orchestration event. The catalog is
  # the source of truth now, so the env being empty changes nothing.
  it "delivers an orchestration event with an empty legacy allowlist" do
    user.update!(marketing_consent: true)

    with_env(make_env) do
      event = described_class.track(
        user: user,
        event_name: "first_workout_completed",
        metadata: { workout_session_id: 456 },
        idempotency_key: "first_workout_completed:empty_allowed"
      )

      expect(event.make_delivery_status).to eq("pending")
    end
  end

  it "records the reason an event was born disabled" do
    user.update!(marketing_consent: true)

    with_env(make_env.merge("MAKE_WEBHOOK_ENABLED" => "false")) do
      event = described_class.track(
        user: user,
        event_name: "first_workout_completed",
        idempotency_key: "first_workout_completed:webhook_off"
      )

      expect(event.make_delivery_status).to eq("disabled")
      expect(event.make_last_error).to eq("make_webhook_disabled_or_unconfigured")
    end
  end

  describe "origin_surface" do
    it "persists a known surface" do
      event = described_class.track(user: user, event_name: "workout_started",
                                    origin_surface: "android")

      expect(event.origin_surface).to eq("android")
    end

    it "leaves it NULL when the producer does not know" do
      event = described_class.track(user: user, event_name: "workout_started")

      expect(event.origin_surface).to be_nil
    end

    # "unknown" is the READING of a NULL, not a value worth storing: writing it
    # would make an unclassified event indistinguishable from one deliberately
    # classified as unknowable.
    it "stores 'unknown' as NULL" do
      event = described_class.track(user: user, event_name: "workout_started",
                                    origin_surface: "unknown")

      expect(event.origin_surface).to be_nil
    end

    it "drops a value outside the known set instead of storing it" do
      event = described_class.track(user: user, event_name: "workout_started",
                                    origin_surface: "'; DROP TABLE users;--")

      expect(event.origin_surface).to be_nil
    end
  end

  it "marks a producer-suppressed event with its own reason" do
    with_env(make_env) do
      event = described_class.track(
        user: user,
        event_name: "push_event_eligible",
        idempotency_key: "push_event_eligible:suppressed",
        suppress_make_delivery: true
      )

      expect(event.make_delivery_status).to eq("disabled")
      expect(event.make_last_error).to eq("suppressed_by_producer")
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

  it "whitelists the AI workout chat events" do
    expect(described_class::EVENTS).to include(
      "ai_workout_chat_started", "ai_workout_message_sent",
      "ai_workout_blocked_security", "ai_workout_blocked_out_of_scope",
      "ai_workout_preview_generated", "ai_workout_preview_adjusted",
      "ai_workout_confirmed", "ai_workout_creation_failed"
    )
  end

  it "whitelists the activation events" do
    expect(described_class::EVENTS).to include(
      "activation_workout_created", "activation_first_workout_completed",
      "activation_reminder_2h_due", "activation_reminder_24h_due",
      "scheduled_workout_reminder_due"
    )
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
