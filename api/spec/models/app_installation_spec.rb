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

  describe "runtime_context" do
    it "accepts a value from the allowlist and rejects anything else" do
      expect(build(:app_installation, runtime_context: "android_native")).to be_valid
      expect(build(:app_installation, runtime_context: "samsung")).not_to be_valid
    end

    it "stays optional — an install may never have been linked" do
      expect(build(:app_installation, runtime_context: nil)).to be_valid
      expect(build(:app_installation, runtime_context: "")).to be_valid
    end
  end

  describe "link signals" do
    it "starts with no attempts and no link timestamps" do
      install = create(:app_installation, :anonymous)

      expect(install.link_attempts_count).to eq(0)
      expect(install.first_authenticated_request_at).to be_nil
      expect(install.first_link_attempt_at).to be_nil
      expect(install.last_link_attempt_at).to be_nil
      expect(install.linked_at).to be_nil
      expect(install.last_link_failure_code).to be_nil
    end
  end

  describe "#associate_user!" do
    it "associates and stamps last_authenticated_at, idempotently" do
      user = create(:user)
      install = create(:app_installation, :anonymous)

      result = install.associate_user!(user)
      install.reload
      expect(result.status).to eq(:linked)
      expect(install.user_id).to eq(user.id)
      expect(install.last_authenticated_at).to be_present
      expect(install.linked_at).to be_present

      previous = install.last_authenticated_at
      second = install.associate_user!(user) # no-op for same user
      install.reload
      expect(second.status).to eq(:already_linked)
      expect(install.last_authenticated_at).to eq(previous)
    end
  end

  describe "linkage scopes" do
    let!(:linked_confirmed) { create(:app_installation, user: create(:user), last_authenticated_at: Time.current) }
    let!(:linked_unconfirmed) { create(:app_installation, user: create(:user), last_authenticated_at: nil) }
    let!(:anonymous_install) { create(:app_installation, :anonymous) }

    it "counts every install with a user as linked" do
      expect(described_class.linked).to contain_exactly(linked_confirmed, linked_unconfirmed)
    end

    it "requires last_authenticated_at for fully_authenticated" do
      expect(described_class.fully_authenticated).to contain_exactly(linked_confirmed)
    end

    it "treats a missing user as anonymous" do
      expect(described_class.anonymous).to contain_exactly(anonymous_install)
    end

    # The old name is kept so existing callers keep working; it must stay an
    # exact alias of :linked, never drift into its own definition.
    it "keeps the deprecated :authenticated scope as an alias of :linked" do
      expect(described_class.authenticated.to_a).to match_array(described_class.linked.to_a)
    end
  end

  it "never exposes device_token_id in JSON" do
    install = create(:app_installation, device_token: create(:device_token))
    expect(install.as_json).not_to have_key("device_token_id")
  end
end
