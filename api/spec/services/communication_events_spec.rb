require "rails_helper"

RSpec.describe CommunicationEvents do
  it "returns configured channels for a known multichannel event" do
    expect(described_class.channels_for("user_inactive_7_days")).to eq(%w[push email])
  end

  it "returns an empty array for known events without communication configured" do
    expect(described_class.channels_for("workout_started")).to eq([])
  end

  it "checks channel support" do
    expect(described_class.supports_channel?("user_inactive_3_days", "push")).to be(true)
    expect(described_class.supports_channel?("user_inactive_3_days", "email")).to be(false)
  end

  it "exposes the technical config of the push journey events" do
    expect(described_class.push_events).to match_array(%w[
      first_workout_not_started_2h first_workout_not_started_24h
      first_workout_completed scheduled_workout_reminder_due
      user_inactive_3_days user_inactive_7_days
    ])
    expect(described_class.notification_type_for("first_workout_not_started_2h")).to eq("activation_reminder")
    expect(described_class.route_for("first_workout_completed")).to eq("/workouts")
    expect(described_class.engagement?("first_workout_not_started_2h")).to be(true)
    expect(described_class.engagement?("first_workout_completed")).to be(false)
  end

  it "rejects unknown events" do
    expect { described_class.channels_for("made_up_event") }
      .to raise_error(CommunicationEvents::UnknownEventError, /made_up_event/)
  end

  it "rejects invalid channels" do
    expect { described_class.validate_channels!(%w[email sms]) }
      .to raise_error(CommunicationEvents::ConfigError, /sms/)
  end

  it "rejects duplicate channels" do
    expect { described_class.validate_channels!(%w[email email]) }
      .to raise_error(CommunicationEvents::ConfigError, /duplicated/)
  end

  it "validates the central config" do
    expect(described_class.validate!).to eq(true)
  end

  it "exposes communication_type and engagement per event" do
    expect(described_class.communication_type_for("trial_day_3")).to eq("lifecycle")
    expect(described_class.communication_type_for("first_workout_not_started_2h")).to eq("activation")
    expect(described_class.communication_type_for("first_workout_completed")).to eq("progress")
    expect(described_class.communication_type_for("user_inactive_7_days")).to eq("retention")
  end

  it "reports enabled state and treats known events without config as disabled" do
    expect(described_class.enabled?("trial_day_3")).to be(true)
    expect(described_class.enabled?("workout_started")).to be(false)
    expect(described_class.channels_for("workout_started")).to eq([])
  end

  it "knows which events are configured event names in the tracker" do
    expect(described_class.known?("trial_day_3")).to be(true)
    expect(described_class.known?("made_up_event")).to be(false)
  end

  it "builds a technical push config with campaign_key equal to event_name" do
    config = described_class.push_config_for("first_workout_not_started_2h")
    expect(config).to eq(
      "notification_type" => "activation_reminder",
      "route" => "/workouts/ready",
      "campaign_key" => "first_workout_not_started_2h"
    )
    expect(described_class.push_config_for("trial_day_3")).to be_nil
  end

  it "builds a technical email config with template_key defaulting to event_name" do
    expect(described_class.email_config_for("trial_day_3")).to eq("template_key" => "trial_day_3")
    expect(described_class.email_config_for("first_workout_not_started_2h")).to be_nil
  end
end
