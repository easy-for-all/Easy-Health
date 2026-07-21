require "rails_helper"

RSpec.describe Make::EventPayloadSerializer do
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
