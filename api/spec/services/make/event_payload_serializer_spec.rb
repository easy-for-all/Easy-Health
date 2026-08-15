require "rails_helper"

RSpec.describe Make::EventPayloadSerializer do
  describe "additive schema 2 fields" do
    let(:serializer_user) { create(:user, time_zone: "America/Sao_Paulo", marketing_consent: true) }

    def payload_for(event_name, metadata: {}, origin_surface: nil)
      event = UserEvent.create!(user: serializer_user, event_name: event_name,
                                occurred_at: Time.current, metadata: metadata,
                                origin_surface: origin_surface)
      described_class.new(event: event, schema_version: 2).as_json
    end

    # The live Make scenario filters on delivery.channels. Renaming or removing
    # it would break every running scenario, so the new name is added ALONGSIDE.
    it "keeps delivery.channels exactly as the Make scenario reads it" do
      payload = payload_for("user_inactive_3_days", metadata: { last_workout_at: 4.days.ago.iso8601 })

      expect(payload[:delivery][:channels]).to eq(%w[push])
      expect(payload[:schema_version]).to eq(2)
    end

    # candidate_channels and channels answer two different questions. They agree
    # whenever nothing narrowed the routing, which is the common case.
    it "reports the catalog channels as candidate_channels" do
      payload = payload_for("user_inactive_7_days", metadata: { last_workout_at: 8.days.ago.iso8601 })

      expect(payload[:delivery][:candidate_channels]).to match_array(%w[push email])
      expect(payload[:delivery][:channels]).to match_array(%w[push email])
    end

    # candidate_channels is business intent and never depends on this user's
    # state; channels is what EasyHealth decided to expose after routing.
    it "keeps candidate_channels intact when routing narrowed the exposed channels" do
      event = UserEvent.create!(user: serializer_user, event_name: "user_inactive_7_days",
                                occurred_at: Time.current,
                                metadata: { last_workout_at: 8.days.ago.iso8601 })
      payload = described_class.new(event: event, schema_version: 2, delivery_channels: %w[push]).as_json

      expect(payload[:delivery][:channels]).to eq(%w[push])
      expect(payload[:delivery][:candidate_channels]).to match_array(%w[push email])
    end

    # The serializer is a pure formatter: it receives resolved channels and never
    # asks who is deliverable. Putting that question back here is what made the
    # payload and make_delivery_channels disagree in the first place.
    it "never consults delivery eligibility" do
      event = UserEvent.create!(user: serializer_user, event_name: "user_inactive_7_days",
                                occurred_at: Time.current,
                                metadata: { last_workout_at: 8.days.ago.iso8601 })
      # Only after the fixtures exist: creating a user legitimately tracks
      # user_created, which resolves channels through the tracker.
      expect(MakeWebhookEligibility).not_to receive(:deliverable_channels)

      described_class.new(event: event, schema_version: 2).as_json
    end

    # A user with no device token, push disabled and no permission still gets
    # push in BOTH arrays: that is push dispatch eligibility, decided later.
    it "keeps push as a channel for a user who cannot receive a push right now" do
      serializer_user.notification_preferences!.update!(push_enabled: false, workout_reminders_enabled: false)
      expect(serializer_user.device_tokens.active).to be_empty

      payload = payload_for("activation_workout_created", metadata: { workout_plan_id: 1 })

      expect(payload[:delivery][:candidate_channels]).to eq(%w[push])
      expect(payload[:delivery][:channels]).to eq(%w[push])
      expect(payload[:push][:notification_type]).to eq("activation_reminder")
    end

    it "mirrors notification_type and route into delivery without emptying the push block" do
      payload = payload_for("first_workout_completed", metadata: { workout_session_id: 1 })

      expect(payload[:delivery][:notification_type]).to eq("progress_update")
      expect(payload[:delivery][:route]).to eq("/workouts")
      expect(payload[:push][:notification_type]).to eq("progress_update")
      expect(payload[:push][:route]).to eq("/workouts")
    end

    it "reports the producing surface" do
      payload = payload_for("first_workout_completed", metadata: { workout_session_id: 1 },
                            origin_surface: "android")

      expect(payload[:origin_surface]).to eq("android")
    end

    it "reports an unclassified event as unknown rather than guessing" do
      payload = payload_for("first_workout_completed", metadata: { workout_session_id: 1 })

      expect(payload[:origin_surface]).to eq("unknown")
    end

    it "carries the reminder timing the Make scenario needs" do
      activation = {
        plan_id: 1, reminder_local_date: Date.current.iso8601,
        preferred_workout_time: "07:00", reminder_time: "06:30",
        reminder_due_at: Time.current.iso8601, reminder_lead_minutes: 30,
        timezone: "America/Sao_Paulo", detected_at: Time.current.iso8601
      }
      payload = payload_for("scheduled_workout_reminder_due", metadata: { activation: activation })

      context = payload[:context][:activation]
      expect(context["preferred_workout_time"]).to eq("07:00")
      expect(context["reminder_due_at"]).to be_present
      expect(context["reminder_lead_minutes"]).to eq(30)
      expect(payload[:user][:timezone]).to eq("America/Sao_Paulo")
    end
  end

  let(:user) { create(:user, marketing_consent: true, time_zone: "America/Sao_Paulo") }

  def build_event(event_name:, metadata: {}, source: "relationship_daily")
    UserEvent.create!(
      user: user,
      event_name: event_name,
      occurred_at: Time.zone.parse("2026-07-18 15:06:35"),
      source: source,
      metadata: metadata
    )
  end

  it "keeps the schema version 1 payload compatible" do
    event = build_event(event_name: "first_workout_completed", metadata: { workout_session_id: 10 })

    payload = described_class.new(event: event, schema_version: 1).as_json

    expect(payload[:schema_version]).to eq(1)
    expect(payload).not_to have_key(:delivery)
    expect(payload).not_to have_key(:context)
    expect(payload[:source]).to eq("relationship_daily")
    expect(payload.dig(:user, :email)).to be_nil
  end

  it "serializes schema version 2 with delivery channels, push block, context and trigger_source" do
    plan = user.workout_plans.create!(active: true, created_at: Time.zone.parse("2026-07-18 13:00:00"))
    event = build_event(
      event_name: "first_workout_not_started_2h",
      metadata: {
        workout_plan_id: plan.id,
        first_workout_created_at: "2026-07-18T13:00:00Z",
        source: "manual_test",
        token: "must-not-leak",
        nested: { api_key: "nope", safe: "ok" }
      }
    )

    payload = described_class.new(event: event, schema_version: 2).as_json

    expect(payload[:schema_version]).to eq(2)
    expect(payload[:source]).to eq("easyhealth_backend")
    expect(payload.dig(:delivery, :channels)).to eq(%w[push])
    # Push descriptor: technical only, NEVER title/body.
    expect(payload[:push]).to eq(
      notification_type: "activation_reminder",
      route: "/workouts/ready",
      campaign_key: "first_workout_not_started_2h"
    )
    expect(payload.dig(:context, :first_workout_created_at)).to be_present
    expect(payload.dig(:context, :hours_since_creation)).to eq(2)
    expect(payload.dig(:metadata, "trigger_source")).to eq("manual_test")
    expect(payload[:metadata]).not_to have_key("source")
    expect(JSON.generate(payload)).not_to match(/token|api_key|must-not-leak|nope|"title"|"body"/i)
  end

  it "enriches delivery with communication_type and engagement, and adds an email block" do
    event = build_event(event_name: "trial_day_3", metadata: { days_since_trial_start: 3 })

    payload = described_class.new(event: event, schema_version: 2).as_json

    expect(payload[:delivery]).to include(
      channels: %w[email],
      communication_type: "lifecycle",
      engagement: false
    )
    expect(payload[:email]).to eq(template_key: "trial_day_3")
    expect(payload).not_to have_key(:push)
  end

  it "adds both email and push blocks for a multichannel event" do
    session = user.workout_sessions.create!(
      status: "completed", completion_status: "completed",
      completed_at: 8.days.ago, duration_minutes: 30
    )
    event = build_event(
      event_name: "user_inactive_7_days",
      metadata: { last_workout_at: session.completed_at.iso8601 }
    )

    payload = described_class.new(event: event, schema_version: 2).as_json

    expect(payload.dig(:delivery, :channels)).to eq(%w[push email])
    expect(payload.dig(:delivery, :communication_type)).to eq("retention")
    expect(payload[:email]).to eq(template_key: "user_inactive_7_days")
    expect(payload.dig(:push, :campaign_key)).to eq("user_inactive_7_days")
  end

  it "returns an empty channel array for known events without configured communication" do
    event = build_event(event_name: "workout_started")

    payload = described_class.new(event: event, schema_version: 2).as_json

    expect(payload.dig(:delivery, :channels)).to eq([])
    expect(payload[:context]).to eq({})
  end

  it "raises when a required context field is missing" do
    event = build_event(event_name: "workout_created_not_started")

    expect { described_class.new(event: event, schema_version: 2).as_json }
      .to raise_error(Make::EventPayloadSerializer::IncompleteEventError, /workout_id/)
  end

  it "builds context for first_workout_completed" do
    session = user.workout_sessions.create!(
      status: "completed",
      completion_status: "completed",
      completed_at: Time.zone.parse("2026-07-18 13:00:00"),
      duration_minutes: 42
    )
    event = build_event(
      event_name: "first_workout_completed",
      metadata: { workout_session_id: session.id }
    )

    payload = described_class.new(event: event, schema_version: 2).as_json

    expect(payload.dig(:context, :workout_session_id)).to eq(session.id)
    expect(payload.dig(:context, :duration_minutes)).to eq(42)
  end

  it "builds context and delivery campaign for scheduled_workout_reminder_due" do
    plan = user.workout_plans.create!(active: true)
    day = plan.workout_days.create!(name: "Treino A", day_of_week: 1)
    event = build_event(
      event_name: "scheduled_workout_reminder_due",
      metadata: {
        campaign: "first_workout_scheduled_reminder_v1",
        activation: {
          plan_id: plan.id,
          workout_id: day.id,
          preferred_workout_time: "07:00",
          reminder_time: "06:30",
          reminder_local_date: "2026-07-21",
          reminder_number: 1,
          maximum_reminders: 3,
          days_since_workout_created: 1,
          first_workout_completed: false
        }
      }
    )

    payload = described_class.new(event: event, schema_version: 2).as_json

    expect(payload.dig(:delivery, :channels)).to eq(%w[push])
    expect(payload.dig(:delivery, :campaign)).to eq("first_workout_scheduled_reminder_v1")
    expect(payload[:push]).to eq(
      notification_type: "activation_reminder",
      route: "/workouts/ready",
      campaign_key: "scheduled_workout_reminder_due"
    )
    expect(payload.dig(:context, :activation, "plan_id")).to eq(plan.id)
    expect(payload.dig(:context, :activation, "workout_id")).to eq(day.id)
    expect(payload.dig(:context, :activation, "reminder_number")).to eq(1)
    expect(JSON.generate(payload)).not_to match(/"title"|"body"|device_token|fcm_token/i)
  end

  it "rejects invalid schema versions clearly" do
    event = build_event(event_name: "workout_started")

    expect { described_class.new(event: event, schema_version: 3).as_json }
      .to raise_error(ArgumentError, /MAKE_EVENT_SCHEMA_VERSION/)
  end
end
