require "rails_helper"

RSpec.describe CommunicationTime do
  describe ".zone_for" do
    it "uses notification preferences before the user timezone" do
      user = create(:user, time_zone: "America/New_York")
      user.notification_preferences!.update!(timezone: "Europe/Lisbon")

      expect(described_class.zone_name_for(user)).to eq("Europe/Lisbon")
    end

    it "uses users.time_zone when notification preferences have no timezone" do
      user = create(:user, time_zone: "America/New_York")
      user.notification_preferences!.update!(timezone: nil)

      expect(described_class.zone_name_for(user)).to eq("America/New_York")
    end

    it "uses a linked Android installation only after explicit user sources" do
      user = create(:user, time_zone: nil)
      user.notification_preferences!.update!(timezone: nil)
      create(:app_installation, user: user, timezone: "Europe/Lisbon", last_seen_at: 1.hour.ago)

      expect(described_class.zone_name_for(user)).to eq("Europe/Lisbon")
    end

    it "does not let AppInstallation overwrite notification preferences" do
      user = create(:user, time_zone: "America/New_York")
      user.notification_preferences!.update!(timezone: "America/Sao_Paulo")
      create(:app_installation, user: user, timezone: "Europe/Lisbon", last_seen_at: 1.hour.ago)

      expect(described_class.zone_name_for(user)).to eq("America/Sao_Paulo")
    end

    it "falls back safely when saved timezones are invalid" do
      user = create(:user, time_zone: "Mars/Olympus")
      user.notification_preferences!.update!(timezone: "Moon/Base")

      expect(Rails.logger).to receive(:warn).with("[communication_time] invalid_timezone source=notification_preferences")
      expect(Rails.logger).to receive(:warn).with("[communication_time] invalid_timezone source=user")

      expect(described_class.zone_name_for(user)).to eq("America/Sao_Paulo")
    end
  end

  describe ".default_zone_name" do
    it "uses the configured IANA timezone when valid" do
      with_env("COMMUNICATION_DEFAULT_TIMEZONE" => "Europe/Lisbon") do
        expect(described_class.default_zone_name).to eq("Europe/Lisbon")
      end
    end

    it "falls back to Sao Paulo when configured with an invalid timezone" do
      with_env("COMMUNICATION_DEFAULT_TIMEZONE" => "Not/AZone") do
        expect(described_class.default_zone_name).to eq("America/Sao_Paulo")
      end
    end
  end
end
