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

  it "creates one installation per android device_token and stamps provenance" do
    user = create(:user)
    token = create(:device_token, user: user, platform: "android", app_version: "1.1.0")

    described_class.new(dry_run: false).call

    install = AppInstallation.find_by(installation_id: "dt-#{token.id}")
    expect(install).to be_present
    expect(install.source).to eq("backfill_device_token")
    expect(install.platform).to eq("android")
    expect(install.native).to be(true)
    expect(install.user_id).to eq(user.id)
    expect(install.device_token_id).to eq(token.id)
    expect(install.app_version).to eq("1.1.0")
    expect(install.installed_at).to be_nil # never faked
    expect(install.first_seen_at).to be_present
  end

  it "is idempotent (re-run creates no duplicates)" do
    user = create(:user)
    create(:device_token, user: user, platform: "android")

    described_class.new(dry_run: false).call
    second = described_class.new(dry_run: false).call

    expect(AppInstallation.count).to eq(1)
    expect(second.installations_created).to eq(0)
    expect(second.installations_existing).to eq(1)
  end

  it "backfills activation_platform='android' only when blank" do
    android_user = create(:user, activation_platform: nil)
    create(:device_token, user: android_user, platform: "android")
    already = create(:user, activation_platform: "web")
    create(:device_token, user: already, platform: "android")

    described_class.new(dry_run: false).call

    expect(android_user.reload.activation_platform).to eq("android")
    expect(already.reload.activation_platform).to eq("web") # never overwritten
  end
end
