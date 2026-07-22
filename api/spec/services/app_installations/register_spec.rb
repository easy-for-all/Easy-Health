require "rails_helper"

RSpec.describe AppInstallations::Register do
  before { allow(described_class).to receive(:enabled?).and_return(true) }

  def register(user: nil, installation_id: "inst-1", attributes: {})
    described_class.new(user: user, installation_id: installation_id, attributes: attributes).call
  end

  it "creates an anonymous installation and stamps the timeline" do
    result = register(attributes: { platform: "android", native: true, app_version: "1.2.0" })

    expect(result.ok).to be(true)
    expect(result.created).to be(true)
    install = result.installation
    expect(install.user_id).to be_nil
    expect(install.platform).to eq("android")
    expect(install.first_seen_at).to be_present
    expect(install.tracking_started_at).to be_present
    expect(install.last_seen_at).to be_present
  end

  it "is idempotent by installation_id (upsert, not duplicate)" do
    register(installation_id: "same", attributes: { app_version: "1.0.0" })
    first_seen = AppInstallation.find_by(installation_id: "same").first_seen_at

    result = register(installation_id: "same", attributes: { app_version: "1.1.0" })
    expect(result.created).to be(false)
    expect(AppInstallation.where(installation_id: "same").count).to eq(1)
    install = AppInstallation.find_by(installation_id: "same")
    expect(install.app_version).to eq("1.1.0")
    expect(install.first_seen_at).to eq(first_seen) # never rewritten
  end

  it "associates the current user and stamps last_authenticated_at" do
    user = create(:user)
    result = register(user: user, installation_id: "inst-auth")
    expect(result.installation.user_id).to eq(user.id)
    expect(result.installation.last_authenticated_at).to be_present
  end

  it "associates a previously anonymous install to the user on a later call" do
    register(installation_id: "inst-x")
    expect(AppInstallation.find_by(installation_id: "inst-x").user_id).to be_nil

    user = create(:user)
    register(user: user, installation_id: "inst-x")
    expect(AppInstallation.find_by(installation_id: "inst-x").user_id).to eq(user.id)
  end

  it "ignores non-allowlisted attributes (e.g. a forged user_id / fcm_token)" do
    other = create(:user)
    result = register(
      installation_id: "inst-forge",
      attributes: { user_id: other.id, fcm_token: "secret", platform: "android" }
    )
    expect(result.installation.user_id).to be_nil
    expect(result.installation).not_to respond_to(:fcm_token)
  end

  it "coerces boolean-ish fields" do
    result = register(attributes: { push_enabled: "true", analytics_consent: "false", native: "true" })
    expect(result.installation.push_enabled).to be(true)
    expect(result.installation.analytics_consent).to be(false)
  end

  describe "install referrer" do
    before { allow(described_class).to receive(:install_referrer_enabled?).and_return(true) }

    it "stores the first valid attribution" do
      result = register(
        installation_id: "inst-ref",
        attributes: { install_referrer: "utm_source=google", utm_source: "google", utm_campaign: "launch" }
      )
      expect(result.installation.install_referrer).to eq("utm_source=google")
      expect(result.installation.utm_source).to eq("google")
    end

    it "never overwrites an existing referrer with a blank" do
      register(installation_id: "inst-ref2", attributes: { install_referrer: "utm_source=fb" })
      register(installation_id: "inst-ref2", attributes: { install_referrer: "" })
      expect(AppInstallation.find_by(installation_id: "inst-ref2").install_referrer).to eq("utm_source=fb")
    end

    it "ignores referrer when the flag is off" do
      allow(described_class).to receive(:install_referrer_enabled?).and_return(false)
      result = register(installation_id: "inst-ref3", attributes: { install_referrer: "utm_source=x" })
      expect(result.installation.install_referrer).to be_nil
    end
  end

  it "is a no-op when the feature flag is disabled" do
    allow(described_class).to receive(:enabled?).and_return(false)
    result = register
    expect(result.ok).to be(false)
    expect(AppInstallation.count).to eq(0)
  end

  it "returns not-ok for a blank installation_id without raising" do
    result = register(installation_id: "  ")
    expect(result.ok).to be(false)
    expect(AppInstallation.count).to eq(0)
  end
end
