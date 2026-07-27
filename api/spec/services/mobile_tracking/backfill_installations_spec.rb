require "rails_helper"

RSpec.describe MobileTracking::BackfillInstallations do
  it "reports without writing in dry-run" do
    user = create(:user)
    create(:device_token, user: user, platform: "android")

    report = described_class.new(dry_run: true).call

    expect(report.dry_run).to be(true)
    expect(report.device_tokens_scanned).to eq(1)
    expect(report.installations_created).to eq(1)
    expect(report.activation_platform_backfilled).to eq(1)
    expect(AppInstallation.count).to eq(0)
    expect(user.reload.activation_platform).to be_nil
  end

  it "stays read-only even when dry_run is false" do
    user = create(:user)
    token = create(:device_token, user: user, platform: "android", app_version: "1.1.0")

    report = described_class.new(dry_run: false).call

    expect(report.dry_run).to be(false)
    expect(report.installations_created).to eq(1)
    expect(AppInstallation.find_by(installation_id: "dt-#{token.id}")).to be_nil
    expect(user.reload.activation_platform).to be_nil
  end

  it "reports existing historical candidates without creating duplicates" do
    user = create(:user)
    token = create(:device_token, user: user, platform: "android")
    create(:app_installation, installation_id: "dt-#{token.id}", platform: "android")

    report = described_class.new(dry_run: false).call

    expect(AppInstallation.count).to eq(1)
    expect(report.installations_created).to eq(0)
    expect(report.installations_existing).to eq(1)
  end

  it "reports activation_platform candidates without writing users" do
    android_user = create(:user, activation_platform: nil)
    create(:device_token, user: android_user, platform: "android")
    already = create(:user, activation_platform: "web")
    create(:device_token, user: already, platform: "android")

    report = described_class.new(dry_run: false).call

    expect(report.activation_platform_backfilled).to eq(1)
    expect(android_user.reload.activation_platform).to be_nil
    expect(already.reload.activation_platform).to eq("web") # never overwritten
  end
end
