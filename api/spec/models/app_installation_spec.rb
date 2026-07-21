require "rails_helper"

RSpec.describe AppInstallation, type: :model do
  it "requires a unique installation_id" do
    create(:app_installation, installation_id: "dup")
    dup = build(:app_installation, installation_id: "dup")
    expect(dup).not_to be_valid
  end

  it "coerces an unknown platform to 'unknown' and forces native false" do
    install = build(:app_installation, platform: "linux", native: true)
    install.valid?
    expect(install.platform).to eq("unknown")
    expect(install.native).to be(false)
  end

  it "forces native false for web/pwa platforms" do
    expect(build(:app_installation, platform: "web", native: true).tap(&:valid?).native).to be(false)
    expect(build(:app_installation, platform: "pwa", native: true).tap(&:valid?).native).to be(false)
  end

  it "keeps native true for android" do
    expect(build(:app_installation, platform: "android", native: true).tap(&:valid?).native).to be(true)
  end

  it "rejects an unknown notification_permission" do
    expect(build(:app_installation, notification_permission: "maybe")).not_to be_valid
    expect(build(:app_installation, notification_permission: "granted")).to be_valid
  end

  describe "#associate_user!" do
    it "associates and stamps last_authenticated_at, idempotently" do
      user = create(:user)
      install = create(:app_installation, :anonymous)

      install.associate_user!(user)
      expect(install.user_id).to eq(user.id)
      expect(install.last_authenticated_at).to be_present

      previous = install.last_authenticated_at
      install.associate_user!(user) # no-op for same user
      expect(install.last_authenticated_at).to eq(previous)
    end
  end

  it "never exposes device_token_id in JSON" do
    install = create(:app_installation, device_token: create(:device_token))
    expect(install.as_json).not_to have_key("device_token_id")
  end
end
