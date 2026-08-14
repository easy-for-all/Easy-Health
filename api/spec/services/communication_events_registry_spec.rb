require "rails_helper"

# Structural guard for config/communication_events.yml — the single source of
# truth for orchestration events. The boot initializer already calls
# CommunicationEvents.validate!, but it only logs in production; this suite
# fails the BUILD, which is where a broken catalog has to be caught.
#
# Every example runs against the real YAML on purpose: the value of this file is
# that it breaks when someone edits the catalog wrongly, not that it exercises
# fixtures.
RSpec.describe "communication events registry" do
  let(:catalog) { CommunicationEvents }
  let(:raw_yaml) { Rails.root.join("config/communication_events.yml").read }

  it "only configures events the tracker knows how to emit" do
    unknown = catalog.configured_event_names - RelationshipEventTracker::EVENTS.map(&:to_s)

    expect(unknown).to be_empty,
      "eventos no YAML ausentes de RelationshipEventTracker::EVENTS: #{unknown.join(', ')}"
  end

  it "gives every orchestration event at least one channel" do
    channelless = catalog.orchestration_event_names.reject { |name| catalog.channels_for(name).any? }

    expect(channelless).to be_empty
  end

  it "only uses known channels" do
    invalid = catalog.configured_event_names.flat_map do |name|
      catalog.channels_for(name) - CommunicationEvents::ALLOWED_CHANNELS
    end.uniq

    expect(invalid).to be_empty, "canais desconhecidos: #{invalid.join(', ')}"
  end

  it "gives every push event the technical descriptor Make needs" do
    aggregate_failures do
      catalog.push_events.each do |name|
        expect(catalog.notification_type_for(name)).to be_present, "#{name}: notification_type ausente"
        expect(catalog.route_for(name)).to be_present, "#{name}: route ausente"
        expect(CommunicationEvents::COMMUNICATION_TYPES).to include(catalog.communication_type_for(name)),
          "#{name}: communication_type inválido"
      end
    end
  end

  # The catalog can be structurally valid and still produce a payload the Make
  # scenario cannot consume. Serializing one event of each configured type here
  # catches a REQUIRED_CONTEXT entry that no producer can ever satisfy.
  it "can serialize a payload for every configured event" do
    user = create(:user, time_zone: "America/Sao_Paulo", marketing_consent: true)

    failures = catalog.configured_event_names.filter_map do |name|
      event = UserEvent.new(
        id: 0,
        user: user,
        event_name: name,
        occurred_at: Time.current,
        source: "spec",
        metadata: registry_metadata_for(name),
        payload_json: {}
      )
      Make::EventPayloadSerializer.new(event: event, schema_version: 2).as_json
      nil
    rescue StandardError => e
      "#{name}: #{e.class}: #{e.message}"
    end

    expect(failures).to be_empty, failures.join("\n")
  end

  it "has no duplicated event key" do
    keys = raw_yaml.lines.filter_map { |line| line[/\A([a-z0-9_]+):/, 1] }

    expect(keys).to eq(keys.uniq), "chaves duplicadas: #{(keys - keys.uniq).uniq.join(', ')}"
  end

  it "keeps a disabled event out of the orchestration set" do
    allow(catalog).to receive(:config_for).and_call_original
    allow(catalog).to receive(:config_for).with("churn_risk")
      .and_return({ "enabled" => false, "channels" => %w[email] })

    expect(catalog.orchestration_event_names).not_to include("churn_risk")
  end

  # Minimum context each event needs to satisfy Make::EventPayloadSerializer::
  # REQUIRED_CONTEXT. Mirrors what the real producers write.
  def registry_metadata_for(event_name)
    case event_name
    when "first_workout_not_started_2h", "first_workout_not_started_24h"
      { "first_workout_created_at" => 2.hours.ago.iso8601, "workout_plan_id" => 1 }
    when "first_workout_created", "plan_created_but_not_used"
      { "workout_plan_id" => 1 }
    when "workout_created_not_started"
      { "workout_id" => 1 }
    when "first_workout_completed"
      { "workout_session_id" => 1, "workout_id" => 1, "completed_at" => Time.current.iso8601 }
    when "scheduled_workout_reminder_due"
      { "activation" => { "plan_id" => 1, "reminder_local_date" => Date.current.iso8601 } }
    when /\Auser_inactive_/
      { "last_workout_at" => 5.days.ago.iso8601, "days_since_last_workout" => 5 }
    else
      {}
    end
  end
end
