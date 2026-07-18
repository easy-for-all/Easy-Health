require "rails_helper"

RSpec.describe CommunicationEvents do
  it "returns configured channels for a known multichannel event" do
    expect(described_class.channels_for("workout_created_not_started")).to eq(%w[email push])
  end

  it "returns an empty array for known events without communication configured" do
    expect(described_class.channels_for("workout_started")).to eq([])
  end

  it "checks channel support" do
    expect(described_class.supports_channel?("user_inactive_3_days", "push")).to be(true)
    expect(described_class.supports_channel?("user_inactive_3_days", "email")).to be(false)
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
end
