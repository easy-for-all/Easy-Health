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

  describe "build scopes" do
    # app_build is a free-form string coming from the client.
    {
      nil => :legacy,
      "" => :legacy,
      "unknown" => :legacy,
      "1.0.45" => :legacy,
      "44" => :legacy,
      "45" => :current,
      "0045" => :current,
      "46" => :current,
      "120" => :current
    }.each do |build_value, expected|
      it "classifies app_build #{build_value.inspect} as #{expected}" do
        install = create(:app_installation, app_build: build_value)

        if expected == :current
          expect(described_class.current_build).to include(install)
          expect(described_class.legacy_build).not_to include(install)
        else
          expect(described_class.legacy_build).to include(install)
          expect(described_class.current_build).not_to include(install)
        end
      end
    end

    it "never raises on a mixed set of valid and malformed builds" do
      %w[45 44 unknown 0045].each { |b| create(:app_installation, app_build: b) }
      create(:app_installation, app_build: nil)

      expect { described_class.current_build.count }.not_to raise_error
      expect(described_class.current_build.count).to eq(2)
      expect(described_class.legacy_build.count).to eq(3)
    end
  end

  it "never exposes device_token_id in JSON" do
    install = create(:app_installation, device_token: create(:device_token))
    expect(install.as_json).not_to have_key("device_token_id")
  end
end
