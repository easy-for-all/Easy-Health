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

  it "serializes schema version 2 with delivery channels, context and trigger_source" do
    plan = user.workout_plans.create!(active: true, created_at: Time.zone.parse("2026-07-18 14:00:00"))
    event = build_event(
      event_name: "workout_created_not_started",
      metadata: {
        workout_plan_id: plan.id,
        source: "manual_test",
        token: "must-not-leak",
        nested: { api_key: "nope", safe: "ok" }
      }
    )

    payload = described_class.new(event: event, schema_version: 2).as_json

    expect(payload[:schema_version]).to eq(2)
    expect(payload[:source]).to eq("easyhealth_backend")
    expect(payload.dig(:delivery, :channels)).to eq(%w[email push])
    expect(payload.dig(:context, :workout_id)).to eq(plan.id)
    expect(payload.dig(:context, :plan_id)).to eq(plan.id)
    expect(payload.dig(:context, :minutes_since_creation)).to eq(66)
    expect(payload.dig(:metadata, "trigger_source")).to eq("manual_test")
    expect(payload[:metadata]).not_to have_key("source")
    expect(JSON.generate(payload)).not_to match(/token|api_key|must-not-leak|nope/i)
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

  it "rejects invalid schema versions clearly" do
    event = build_event(event_name: "workout_started")

    expect { described_class.new(event: event, schema_version: 3).as_json }
      .to raise_error(ArgumentError, /MAKE_EVENT_SCHEMA_VERSION/)
  end
end
