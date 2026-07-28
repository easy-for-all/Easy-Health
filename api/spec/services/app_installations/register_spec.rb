require "rails_helper"

RSpec.describe AppInstallations::Register do
  include ActiveSupport::Testing::TimeHelpers

  before { allow(described_class).to receive(:enabled?).and_return(true) }

  def register(user: nil, installation_id: "inst-1", attributes: {}, session_started: false)
    described_class.new(
      user: user, installation_id: installation_id,
      attributes: attributes, session_started: session_started
    ).call
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
    expect(result.link_result.status).to eq(:linked)
    expect(result.installation.user_id).to eq(user.id)
    expect(result.installation.first_authenticated_request_at).to be_present
    expect(result.installation.linked_at).to be_present
    expect(result.installation.last_authenticated_at).to be_present
  end

  it "associates a previously anonymous install to the user on a later call" do
    register(installation_id: "inst-x")
    expect(AppInstallation.find_by(installation_id: "inst-x").user_id).to be_nil

    user = create(:user)
    result = register(user: user, installation_id: "inst-x")
    install = AppInstallation.find_by(installation_id: "inst-x")
    expect(result.link_result.status).to eq(:linked)
    expect(install.user_id).to eq(user.id)
    expect(install.first_authenticated_request_at).to be_present
    expect(install.linked_at).to be_present
  end

  it "never steals an installation already owned by another user" do
    owner = create(:user)
    register(user: owner, installation_id: "inst-owned")
    previous = AppInstallation.find_by(installation_id: "inst-owned").last_authenticated_at

    other = create(:user)
    allow(Rails.logger).to receive(:warn)
    result = travel_to(2.hours.from_now) { register(user: other, installation_id: "inst-owned") }

    install = AppInstallation.find_by(installation_id: "inst-owned")
    expect(result.link_result.status).to eq(:conflict)
    expect(install.user_id).to eq(owner.id)
    expect(install.last_authenticated_at).to be_within(1.second).of(previous)
    expect(install.last_link_failure_code).to eq("user_conflict")
    expect(Rails.logger).to have_received(:warn).with(/installation_link_conflict/)
  end

  it "keeps the saved installation when linking fails" do
    user = create(:user)
    failure = AppInstallations::LinkToUser::Result.new(
      success: false,
      status: :validation_failed,
      installation: nil,
      failure_code: "validation_failed"
    )
    allow(AppInstallations::LinkToUser).to receive(:call).and_return(failure)

    result = register(user: user, installation_id: "inst-link-fail", attributes: { platform: "android" })
    install = AppInstallation.find_by(installation_id: "inst-link-fail")

    expect(result.ok).to be(true)
    expect(result.link_result).to eq(failure)
    expect(install).to be_present
    expect(install.user_id).to be_nil
    expect(install.first_authenticated_request_at).to be_present
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

  describe "session timeline (last_seen_at vs last_session_at)" do
    it "refreshes last_seen_at on every valid contact" do
      register(installation_id: "inst-seen", attributes: { platform: "android", native: true })
      first_seen_at = AppInstallation.find_by(installation_id: "inst-seen").last_seen_at

      travel_to(1.hour.from_now) do
        register(installation_id: "inst-seen", attributes: { platform: "android", native: true })
      end
      expect(AppInstallation.find_by(installation_id: "inst-seen").last_seen_at).to be > first_seen_at
    end

    it "does NOT stamp last_session_at on a plain refresh (no session_started)" do
      result = register(installation_id: "inst-nosess", attributes: { platform: "android", native: true })
      expect(result.installation.last_session_at).to be_nil
    end

    it "stamps last_session_at only when session_started is signalled" do
      result = register(
        installation_id: "inst-sess", session_started: true,
        attributes: { platform: "android", native: true }
      )
      expect(result.installation.last_session_at).to be_present
    end
  end

  describe "activation_platform association" do
    it "fills a blank activation_platform when a native Android install is associated" do
      user = create(:user)
      expect(user.activation_platform).to be_nil

      register(user: user, installation_id: "inst-ap", attributes: { platform: "android", native: true })
      expect(user.reload.activation_platform).to eq("android")
    end

    it "never overwrites an existing activation_platform" do
      user = create(:user)
      user.update_column(:activation_platform, "web")

      register(user: user, installation_id: "inst-ap2", attributes: { platform: "android", native: true })
      expect(user.reload.activation_platform).to eq("web")
    end

    it "does not set activation_platform for a web install" do
      user = create(:user)
      register(user: user, installation_id: "inst-web", attributes: { platform: "web", native: false })
      expect(user.reload.activation_platform).to be_nil
    end

    it "does not set activation_platform for a pwa install" do
      user = create(:user)
      register(user: user, installation_id: "inst-pwa", attributes: { platform: "pwa", native: false })
      expect(user.reload.activation_platform).to be_nil
    end

    it "leaves activation_platform untouched for an anonymous install" do
      result = register(installation_id: "inst-anon", attributes: { platform: "android", native: true })
      expect(result.installation.user_id).to be_nil
      expect(result.installation.last_authenticated_at).to be_nil
    end
  end

  it "registers a native Android install without any DeviceToken" do
    result = register(installation_id: "inst-nodt", attributes: { platform: "android", native: true })
    expect(result.ok).to be(true)
    expect(result.installation.device_token_id).to be_nil
    expect(result.installation.source).to eq("register")
  end

  it "keeps activation_platform and consent_source as distinct semantics" do
    user = create(:user)
    user.update_column(:consent_source, "web") # consent collected on the web form (inside the WebView)

    register(user: user, installation_id: "inst-distinct", attributes: { platform: "android", native: true })

    user.reload
    expect(user.activation_platform).to eq("android") # runtime platform
    expect(user.consent_source).to eq("web")          # where consent was collected
  end

  it "is a no-op when the feature flag is disabled" do
    allow(described_class).to receive(:enabled?).and_return(false)
    result = register
    expect(result.ok).to be(false)
    expect(result.status).to eq(:disabled)
    expect(AppInstallation.count).to eq(0)
  end

  it "returns not-ok for a blank installation_id without raising" do
    result = register(installation_id: "  ")
    expect(result.ok).to be(false)
    expect(result.status).to eq(:invalid_input)
    expect(AppInstallation.count).to eq(0)
  end

  # find_or_initialize_by + save! is not atomic. Two boots of the same fresh
  # install can both decide to INSERT; the unique index makes one of them lose.
  describe "concurrent creation of the same installation_id" do
    # The row the winning request already committed.
    def simulate_lost_race(installation_id)
      loser = AppInstallation.new(installation_id: installation_id)
      allow(AppInstallation).to receive(:find_or_initialize_by)
        .with(installation_id: installation_id).and_return(loser)
      allow(loser).to receive(:save!).and_raise(
        ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint")
      )
      loser
    end

    it "recovers by reloading the row the winner created, and keeps registering" do
      winner = create(:app_installation, installation_id: "inst-race", app_version: "1.0.0")
      simulate_lost_race("inst-race")

      result = register(installation_id: "inst-race", attributes: { app_version: "2.0.0" })

      expect(result.ok).to be(true)
      expect(result.status).to eq(:registered)
      expect(result.created).to be(false) # the winner created it, not this request
      expect(result.installation.id).to eq(winner.id)
      expect(winner.reload.app_version).to eq("2.0.0") # this request's metadata still landed
      expect(AppInstallation.where(installation_id: "inst-race").count).to eq(1)
    end

    it "still links the user after recovering from the race" do
      create(:app_installation, installation_id: "inst-race-link")
      simulate_lost_race("inst-race-link")
      user = create(:user)

      result = register(user: user, installation_id: "inst-race-link")

      expect(result.link_result.status).to eq(:linked)
      install = AppInstallation.find_by(installation_id: "inst-race-link")
      expect(install.user_id).to eq(user.id)
      expect(install.first_authenticated_request_at).to be_present
    end

    it "never lets the loser overwrite a user_id the winner already linked" do
      owner = create(:user)
      create(:app_installation, installation_id: "inst-race-owned", user: owner, linked_at: 1.hour.ago)
      simulate_lost_race("inst-race-owned")
      other = create(:user)
      allow(Rails.logger).to receive(:warn)

      result = register(user: other, installation_id: "inst-race-owned")

      expect(result.link_result.status).to eq(:conflict)
      expect(AppInstallation.find_by(installation_id: "inst-race-owned").user_id).to eq(owner.id)
    end

    # The likelier shape of the same race: the uniqueness VALIDATOR sees the
    # winner's row first, so save! raises RecordInvalid rather than
    # RecordNotUnique. Reporting that as validation_failed would tell the client
    # its payload is permanently bad about a row that exists.
    it "recovers when the uniqueness validator loses the race, not just the index" do
      winner = create(:app_installation, installation_id: "inst-race-validated", app_version: "1.0.0")
      loser = AppInstallation.new(installation_id: "inst-race-validated")
      allow(AppInstallation).to receive(:find_or_initialize_by)
        .with(installation_id: "inst-race-validated").and_return(loser)
      allow(loser).to receive(:save!) do
        loser.errors.add(:installation_id, :taken)
        raise ActiveRecord::RecordInvalid, loser
      end

      result = register(installation_id: "inst-race-validated", attributes: { app_version: "2.0.0" })

      expect(result.ok).to be(true)
      expect(result.status).to eq(:registered)
      expect(result.created).to be(false)
      expect(winner.reload.app_version).to eq("2.0.0")
    end

    it "still reports a genuine validation error instead of treating it as a race" do
      loser = AppInstallation.new(installation_id: "inst-invalid")
      allow(AppInstallation).to receive(:find_or_initialize_by)
        .with(installation_id: "inst-invalid").and_return(loser)
      allow(loser).to receive(:save!) do
        loser.errors.add(:platform, :inclusion)
        raise ActiveRecord::RecordInvalid, loser
      end

      result = register(installation_id: "inst-invalid")

      expect(result.ok).to be(false)
      expect(result.status).to eq(:validation_failed)
    end

    it "recovers at most once — a reload that finds nothing is reported, not retried" do
      simulate_lost_race("inst-race-gone")
      allow(AppInstallation).to receive(:find_by).and_return(nil)
      allow(Sentry).to receive(:initialized?).and_return(true)
      allow(Sentry).to receive(:capture_exception)

      result = register(installation_id: "inst-race-gone")

      expect(result.ok).to be(false)
      expect(result.status).to eq(:unexpected_error)
      expect(AppInstallation).to have_received(:find_by).once
    end
  end

  it "reports a real validation failure instead of disguising it as success" do
    invalid = AppInstallation.new(installation_id: "inst-invalid")
    allow(AppInstallation).to receive(:find_or_initialize_by).and_return(invalid)
    allow(invalid).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(invalid))

    result = register(installation_id: "inst-invalid")

    expect(result.ok).to be(false)
    expect(result.status).to eq(:validation_failed)
    expect(result.installation).to be_nil
  end

  it "reports an unexpected internal failure as such, and sends it to Sentry" do
    allow(AppInstallation).to receive(:find_or_initialize_by).and_raise(StandardError, "boom")
    allow(Sentry).to receive(:initialized?).and_return(true)
    expect(Sentry).to receive(:capture_exception)

    result = register(installation_id: "inst-boom")

    expect(result.ok).to be(false)
    expect(result.status).to eq(:unexpected_error)
  end
end
