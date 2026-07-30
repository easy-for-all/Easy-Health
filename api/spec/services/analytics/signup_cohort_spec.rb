require "rails_helper"

RSpec.describe Analytics::SignupCohort do
  include ActiveSupport::Testing::TimeHelpers

  # Every temporal assertion is frozen, so a spec never depends on the real clock.
  # 2026-07-27 15:00 UTC == Monday 12:00 in São Paulo, i.e. inside the week the
  # investigation cohort starts on.
  around { |example| travel_to(Time.utc(2026, 7, 27, 15, 0)) { example.run } }

  let(:sp) { ActiveSupport::TimeZone["America/Sao_Paulo"] }

  def user_created_at(time, **attrs)
    create(:user, created_at: time, **attrs)
  end

  describe "window resolution" do
    it "cuts 'desde segunda' at midnight Monday in the reporting zone" do
      window = described_class.new(period: "since_monday").window

      expect(window.first).to eq(sp.parse("2026-07-27 00:00"))
      expect(window.first.utc.hour).to eq(3) # midnight in SP is 03:00Z
    end

    it "cuts 'hoje' at midnight in the reporting zone, not in UTC" do
      expect(described_class.new(period: "today").window.first).to eq(sp.parse("2026-07-27 00:00"))
    end

    it "has no window at all for 'desde sempre'" do
      expect(described_class.new(period: "all").window).to be_nil
    end

    it "falls back to the default period for junk input" do
      expect(described_class.new(period: "lol'; DROP--").period).to eq("since_monday")
    end

    it "ignores a source outside the canonical allow-list" do
      expect(described_class.new(source: "windowsphone").source).to be_nil
      expect(described_class.new(source: "android").source).to eq("android")
    end
  end

  describe "timezone boundaries" do
    # This is the whole reason the service uses ReportingTime and not Time.zone:
    # Time.zone is UTC here, and a UTC week cut starts at 00:00Z Monday, which
    # would drag Sunday-evening Brazilian signups into "desde segunda".
    it "excludes an account created Sunday 23:30 São Paulo (= 02:30Z Monday)" do
      user_created_at(sp.parse("2026-07-26 23:30"))

      summary = described_class.new(period: "since_monday").summary

      expect(summary[:total]).to eq(0)
    end

    it "includes an account created Monday 00:01 São Paulo (= 03:01Z)" do
      user_created_at(sp.parse("2026-07-27 00:01"))

      summary = described_class.new(period: "since_monday").summary

      expect(summary[:total]).to eq(1)
    end

    it "counts the Sunday account under 'desde sempre'" do
      user_created_at(sp.parse("2026-07-26 23:30"))

      expect(described_class.new(period: "all").summary[:total]).to eq(1)
    end
  end

  describe "#summary" do
    it "breaks the cohort down by observed origin" do
      user_created_at(sp.parse("2026-07-27 09:00"), signup_source: "android")
      user_created_at(sp.parse("2026-07-27 10:00"), signup_source: "web")
      user_created_at(sp.parse("2026-07-27 10:30"), signup_source: "web")
      user_created_at(sp.parse("2026-07-27 11:00"), signup_source: "pwa")
      user_created_at(sp.parse("2026-07-27 12:00"), signup_source: "unknown")

      summary = described_class.new(period: "since_monday").summary

      expect(summary[:total]).to eq(5)
      expect(summary[:by_source]).to eq("android" => 1, "web" => 2, "pwa" => 1, "unknown" => 1)
    end

    # A source with zero signups must render as 0, not vanish: a missing card
    # reads as "not instrumented" rather than "nobody came from there".
    it "always reports all four sources, even at zero" do
      expect(described_class.new(period: "since_monday").summary[:by_source].keys)
        .to match_array(%w[android web pwa unknown])
    end

    it "reports the analytics denominator alongside, never instead of, the raw total" do
      user_created_at(sp.parse("2026-07-27 09:00"), signup_source: "web")
      user_created_at(sp.parse("2026-07-27 09:30"), signup_source: "web", test_account: true)

      summary = described_class.new(period: "since_monday").summary

      expect(summary[:total]).to eq(2)
      expect(summary[:reportable_total]).to eq(1)
    end

    it "carries the unknown share as a metric with its own note" do
      user_created_at(sp.parse("2026-07-27 09:00"), signup_source: "unknown")
      user_created_at(sp.parse("2026-07-27 10:00"), signup_source: "web")

      share = described_class.new(period: "since_monday").summary[:unknown_share].as_json

      expect(share[:numerator]).to eq(1)
      expect(share[:denominator]).to eq(2)
      expect(share[:note]).to include("NÃO significa web")
    end

    it "returns zeros and no division error on an empty base" do
      summary = described_class.new(period: "since_monday").summary

      expect(summary[:total]).to eq(0)
      expect(summary[:unknown_share].as_json[:status]).to eq("no_coverage")
    end
  end

  describe "#android_funnel" do
    it "counts installations observed inside the window" do
      create(:app_installation, first_seen_at: sp.parse("2026-07-27 08:00"), last_seen_at: sp.parse("2026-07-27 09:00"))
      create(:app_installation, first_seen_at: sp.parse("2026-05-01 08:00"), last_seen_at: sp.parse("2026-05-01 09:00"))

      expect(described_class.new(period: "since_monday").android_funnel[:installations_observed]).to eq(1)
    end

    it "counts an older installation seen again inside the window" do
      create(:app_installation, first_seen_at: sp.parse("2026-05-01 08:00"), last_seen_at: sp.parse("2026-07-27 11:00"))

      expect(described_class.new(period: "since_monday").android_funnel[:installations_observed]).to eq(1)
    end

    it "ignores non-Android installations" do
      create(:app_installation, platform: "web", native: false,
                                first_seen_at: sp.parse("2026-07-27 08:00"), last_seen_at: sp.parse("2026-07-27 09:00"))

      expect(described_class.new(period: "since_monday").android_funnel[:installations_observed]).to eq(0)
    end

    it "separates linked from anonymous installations against the observed denominator" do
      linked_user = user_created_at(sp.parse("2026-07-27 09:00"), signup_source: "android")
      create(:app_installation, user: linked_user,
                                first_seen_at: sp.parse("2026-07-27 08:00"), last_seen_at: sp.parse("2026-07-27 09:00"))
      create(:app_installation, :anonymous,
             first_seen_at: sp.parse("2026-07-27 08:30"), last_seen_at: sp.parse("2026-07-27 09:30"))

      funnel = described_class.new(period: "since_monday").android_funnel

      expect(funnel[:installations_observed]).to eq(2)
      expect(funnel[:linked_installations].as_json).to include(numerator: 1, denominator: 2)
      expect(funnel[:anonymous_installations]).to eq(1)
    end

    it "counts reached-authentication from the observed authenticated request" do
      create(:app_installation, first_seen_at: sp.parse("2026-07-27 08:00"), last_seen_at: sp.parse("2026-07-27 09:00"),
                                first_authenticated_request_at: sp.parse("2026-07-27 08:30"))
      create(:app_installation, :anonymous,
             first_seen_at: sp.parse("2026-07-27 08:00"), last_seen_at: sp.parse("2026-07-27 09:00"))

      funnel = described_class.new(period: "since_monday").android_funnel

      expect(funnel[:reached_authentication].as_json).to include(numerator: 1, denominator: 2)
    end

    it "counts users created from Android inside the window" do
      user_created_at(sp.parse("2026-07-27 09:00"), signup_source: "android")
      user_created_at(sp.parse("2026-07-20 09:00"), signup_source: "android")
      user_created_at(sp.parse("2026-07-27 10:00"), signup_source: "web")

      expect(described_class.new(period: "since_monday").android_funnel[:users_created_from_android]).to eq(1)
    end

    # THE central guard: an installation showing up long after the account was
    # created proves "this user used Android", never "this account was created
    # from Android".
    it "does not retroactively classify an old account because an installation appeared later" do
      old_user = user_created_at(sp.parse("2026-04-27 09:00"))
      create(:app_installation, user: old_user,
                                first_seen_at: sp.parse("2026-07-27 08:00"), last_seen_at: sp.parse("2026-07-27 09:00"))

      cohort = described_class.new(period: "since_monday")

      expect(old_user.reload.signup_source).to eq("unknown")
      expect(cohort.summary[:by_source]["android"]).to eq(0)
      expect(cohort.android_funnel[:users_created_from_android]).to eq(0)
      # The installation itself IS observed and linked — that is the correct,
      # separate fact.
      expect(cohort.android_funnel[:installations_observed]).to eq(1)
      expect(cohort.android_funnel[:linked_installations].as_json[:numerator]).to eq(1)
    end

    it "reports auth attempt events per event name, always with all four keys" do
      create_attempt_event("android_registration_started", sp.parse("2026-07-27 09:00"))
      create_attempt_event("android_registration_started", sp.parse("2026-07-27 09:05"))
      create_attempt_event("android_registration_failed", sp.parse("2026-07-27 09:10"))
      create_attempt_event("android_registration_started", sp.parse("2026-07-20 09:00")) # before the window

      events = described_class.new(period: "since_monday").android_funnel[:auth_attempt_events]

      expect(events["android_registration_started"]).to eq(2)
      expect(events["android_registration_failed"]).to eq(1)
      expect(events["google_auth_started"]).to eq(0)
      expect(events.keys).to match_array(
        %w[android_registration_started android_registration_failed google_auth_started google_auth_failed]
      )
    end

    it "ignores attempt events attributed to another platform" do
      create_attempt_event("google_auth_started", sp.parse("2026-07-27 09:00"), platform: "web")

      expect(described_class.new(period: "since_monday").android_funnel[:auth_attempt_events]["google_auth_started"]).to eq(0)
    end
  end

  describe "#definitions" do
    it "publishes the resolved window and the reporting zone" do
      definitions = described_class.new(period: "since_monday").definitions

      expect(definitions[:timezone]).to eq("America/Sao_Paulo")
      expect(definitions[:window_from]).to eq("2026-07-27T00:00:00-03:00")
      expect(definitions[:period]).to eq("since_monday")
    end

    it "leaves the window boundaries nil for 'desde sempre'" do
      definitions = described_class.new(period: "all").definitions

      expect(definitions[:window_from]).to be_nil
      expect(definitions[:window_to]).to be_nil
    end

    it "documents every metric the funnel exposes" do
      definitions = described_class.new.definitions

      expect(definitions.keys).to include(
        :installations_observed, :reached_authentication, :users_created_from_android,
        :linked_installations, :anonymous_installations, :auth_attempt_events, :unknown_note
      )
    end
  end

  it "is read-only: computing the cohort mutates nothing" do
    user = user_created_at(sp.parse("2026-07-27 09:00"), signup_source: "android")
    install = create(:app_installation, user: user,
                                        first_seen_at: sp.parse("2026-07-27 08:00"),
                                        last_seen_at: sp.parse("2026-07-27 09:00"))

    expect {
      described_class.new(period: "since_monday").call
    }.not_to change { [ user.reload.updated_at, install.reload.updated_at, ProductAnalyticsEvent.count ] }
  end

  def create_attempt_event(event_name, occurred_at, platform: "android")
    ProductAnalyticsEvent.create!(
      event_name: event_name,
      platform: platform,
      app_surface: "native_shell",
      occurred_at: occurred_at,
      received_at: occurred_at,
      source: "server"
    )
  end
end
