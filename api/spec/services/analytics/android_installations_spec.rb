require "rails_helper"

RSpec.describe Analytics::AndroidInstallations do
  include ActiveSupport::Testing::TimeHelpers

  subject(:result) { described_class.new.call }

  # Every temporal assertion is frozen, so a spec never depends on the real clock.
  around { |example| travel_to(Time.zone.parse("2026-07-26 12:00:00")) { example.run } }

  def android(**attrs)
    create(:app_installation, { platform: "android", native: true }.merge(attrs))
  end

  def android_event(occurred_at: Time.current)
    ProductAnalyticsEvent.create!(
      event_name: "app_opened", event_version: 1, platform: "android",
      app_surface: "native_shell", environment: "test",
      occurred_at: occurred_at, received_at: occurred_at
    )
  end

  describe "empty base" do
    it "returns zeros and never divides by zero" do
      expect(result[:overview][:total_installations]).to eq(0)
      expect(result[:overview][:unique_linked_users]).to eq(0)
      expect(result[:overview][:link_rate].value).to eq(0.0)
      expect(result[:reconciliation][:link_rate].value).to eq(0.0)
      expect(result[:versions]).to eq([])
      expect(result[:health_timeline]).to eq([])
    end
  end

  describe "platform isolation" do
    it "counts only android installs" do
      android
      create(:app_installation, platform: "web", native: false)
      create(:app_installation, platform: "pwa", native: false)
      create(:app_installation, platform: "unknown", native: false)

      expect(result[:overview][:total_installations]).to eq(1)
    end

    it "reports zero when only web/pwa installs exist" do
      create(:app_installation, platform: "web", native: false)
      create(:app_installation, platform: "pwa", native: false)

      expect(result[:overview][:total_installations]).to eq(0)
      expect(result[:overview][:link_rate].denominator).to eq(0)
    end
  end

  describe "linkage" do
    it "separates anonymous from linked installs" do
      android(user: nil)
      android(user: create(:user), last_authenticated_at: Time.current)

      overview = result[:overview]
      expect(overview[:total_installations]).to eq(2)
      expect(overview[:linked_installations]).to eq(1)
      expect(overview[:anonymous_installations]).to eq(1)
      expect(overview[:link_rate].value).to eq(50.0)
    end

    it "requires last_authenticated_at to count as authenticated" do
      android(user: create(:user), last_authenticated_at: Time.current)
      android(user: create(:user), last_authenticated_at: nil)

      expect(result[:overview][:linked_installations]).to eq(2)
      expect(result[:overview][:authenticated_installations]).to eq(1)
      expect(result[:data_quality][:linked_without_last_authenticated_at]).to eq(1)
    end

    it "flags last_authenticated_at without a user as an inconsistency" do
      android(user: nil, last_authenticated_at: Time.current)

      expect(result[:data_quality][:authenticated_at_without_user]).to eq(1)
      expect(result[:overview][:authenticated_installations]).to eq(0)
    end
  end

  describe "users vs installations" do
    it "counts a user with two installs once" do
      user = create(:user)
      android(user: user)
      android(user: user)
      android(user: create(:user))

      overview = result[:overview]
      expect(overview[:linked_installations]).to eq(3)
      expect(overview[:unique_linked_users]).to eq(2)
      expect(overview[:users_with_multiple_installations]).to eq(1)
    end

    it "reports no multi-install users when each user has one install" do
      android(user: create(:user))
      android(user: create(:user))

      expect(result[:overview][:users_with_multiple_installations]).to eq(0)
    end
  end

  describe "reconciliation" do
    it "uses authenticated request observation as the denominator, not build" do
      android(app_build: "34", user: nil, first_authenticated_request_at: 1.hour.ago)
      android(app_build: "45", user: create(:user),
              first_authenticated_request_at: 1.hour.ago, linked_at: 1.hour.ago)
      android(app_build: "unknown", user: create(:user),
              first_authenticated_request_at: 1.hour.ago, linked_at: 1.hour.ago)
      android(app_build: "50", user: create(:user), linked_at: 1.hour.ago) # no observed request

      reconciliation = result[:reconciliation]
      expect(reconciliation[:observed_authenticated_installations]).to eq(3)
      expect(reconciliation[:linked_installations]).to eq(2)
      expect(reconciliation[:link_rate].value).to eq(66.7)
      expect(result[:data_quality][:linked_without_observed_request]).to eq(1)
    end

    it "reports link attempts, conflicts and failures by code" do
      android(first_authenticated_request_at: 1.hour.ago, first_link_attempt_at: 1.hour.ago,
              last_link_failure_code: "user_conflict")
      android(first_authenticated_request_at: 1.hour.ago, first_link_attempt_at: 1.hour.ago,
              last_link_failure_code: "validation_failed")
      android(first_authenticated_request_at: 1.hour.ago, linked_at: 1.hour.ago)

      reconciliation = result[:reconciliation]
      expect(reconciliation[:link_attempted_installations]).to eq(2)
      expect(reconciliation[:conflicts]).to eq(1)
      expect(reconciliation[:failures_by_code]).to include("user_conflict" => 1, "validation_failed" => 1)
    end

    it "treats nil, blank and non-numeric builds as descriptive data-quality only" do
      android(app_build: nil)
      android(app_build: "")
      android(app_build: "unknown")

      expect { result }.not_to raise_error
      expect(result[:reconciliation][:observed_authenticated_installations]).to eq(0)
      expect(result[:data_quality][:missing_app_build]).to eq(2)
      expect(result[:data_quality][:invalid_app_build]).to eq(1)
    end

    it "returns 0.0 instead of NaN when there is no observed authenticated request" do
      android(app_build: "44")

      rate = result[:reconciliation][:link_rate]
      expect(rate.value).to eq(0.0)
      expect(rate.denominator).to eq(0)
      expect(rate.status).to eq("no_coverage")
    end
  end

  describe "activity windows" do
    it "counts 7d and 30d activity from last_seen_at" do
      android(last_seen_at: 1.day.ago)
      android(last_seen_at: 10.days.ago)
      android(last_seen_at: 60.days.ago)

      expect(result[:overview][:active_installations_7d]).to eq(1)
      expect(result[:overview][:active_installations_30d]).to eq(2)
    end

    it "does not count an install that was never seen" do
      android(last_seen_at: nil)

      expect(result[:overview][:active_installations_7d]).to eq(0)
      expect(result[:overview][:active_installations_30d]).to eq(0)
      expect(result[:data_quality][:missing_last_seen_at]).to eq(1)
    end
  end

  describe "groupings" do
    it "groups versions by version and build with linkage breakdown" do
      android(app_version: "1.0.45", app_build: "45", user: create(:user))
      android(app_version: "1.0.45", app_build: "45", user: nil)
      android(app_version: "1.0.44", app_build: "44", user: nil)

      newest = result[:versions].first
      expect(newest[:app_version]).to eq("1.0.45")
      expect(newest[:app_build]).to eq("45")
      expect(newest[:total_installations]).to eq(2)
      expect(newest[:linked_installations]).to eq(1)
      expect(newest[:anonymous_installations]).to eq(1)
      expect(newest[:link_rate].value).to eq(50.0)

      expect(result[:versions].last[:app_build]).to eq("44")
    end

    it "sorts numeric builds newest first and pushes unknown builds last" do
      android(app_build: "44")
      android(app_build: nil)
      android(app_build: "46")

      expect(result[:versions].map { |v| v[:app_build] }).to eq(%w[46 44] + [ nil ])
    end

    it "groups manufacturers with linked and 30d activity" do
      android(device_manufacturer: "samsung", user: create(:user), last_seen_at: 2.days.ago)
      android(device_manufacturer: "samsung", user: nil, last_seen_at: 90.days.ago)
      android(device_manufacturer: "xiaomi", user: nil, last_seen_at: 2.days.ago)

      samsung = result[:manufacturers].find { |m| m[:manufacturer] == "samsung" }
      expect(samsung[:total_installations]).to eq(2)
      expect(samsung[:linked_installations]).to eq(1)
      expect(samsung[:active_installations_30d]).to eq(1)
    end

    it "groups device models under their manufacturer" do
      android(device_manufacturer: "samsung", device_model: "SM-A125M")
      android(device_manufacturer: "samsung", device_model: "SM-A125M")
      android(device_manufacturer: "google", device_model: "sdk_gphone")

      top = result[:device_models].first
      expect(top[:manufacturer]).to eq("samsung")
      expect(top[:device_model]).to eq("SM-A125M")
      expect(top[:total_installations]).to eq(2)
    end

    it "groups operating system versions" do
      android(operating_system_version: "12")
      android(operating_system_version: "12")
      android(operating_system_version: "14")

      expect(result[:operating_system_versions].first)
        .to include(operating_system_version: "12", total_installations: 2)
    end

    it "keeps blank grouping values as nil (labelled only in the UI)" do
      android(device_manufacturer: nil, device_model: nil, operating_system_version: nil)

      expect(result[:manufacturers].first[:manufacturer]).to be_nil
      expect(result[:device_models].first[:device_model]).to be_nil
      expect(result[:operating_system_versions].first[:operating_system_version]).to be_nil
    end

    it "caps every grouping at its documented limit" do
      21.times { |i| android(app_version: "1.0.#{i}", app_build: (100 + i).to_s) }
      11.times { |i| android(device_manufacturer: "brand-#{i}") }
      16.times { |i| android(device_model: "model-#{i}") }
      16.times { |i| android(operating_system_version: "os-#{i}") }

      expect(result[:versions].size).to eq(described_class::VERSIONS_LIMIT)
      expect(result[:manufacturers].size).to eq(described_class::MANUFACTURERS_LIMIT)
      expect(result[:device_models].size).to eq(described_class::DEVICE_MODELS_LIMIT)
      expect(result[:operating_system_versions].size).to eq(described_class::OS_VERSIONS_LIMIT)
    end
  end

  describe "version adoption" do
    it "reports the most used and the latest build" do
      android(app_version: "1.0.44", app_build: "44")
      android(app_version: "1.0.44", app_build: "44")
      android(app_version: "1.0.45", app_build: "45")

      adoption = result[:adoption]
      expect(adoption[:most_used_version]).to eq("1.0.44")
      expect(adoption[:most_used_build]).to eq(44)
      expect(adoption[:latest_build]).to eq(45)
      expect(adoption[:latest_build_installations]).to eq(1)
      expect(adoption[:latest_build_share].value).to eq(33.3)
    end

    it "handles a base without any numeric build" do
      android(app_build: "unknown", app_version: nil)

      adoption = result[:adoption]
      expect(adoption[:latest_build]).to be_nil
      expect(adoption[:most_used_build]).to be_nil
      expect(adoption[:most_used_version]).to be_nil
      expect(adoption[:latest_build_share].value).to eq(0.0)
    end
  end

  describe "health timeline" do
    it "reports one row per day with that day's link rate, newest first" do
      android(first_authenticated_request_at: 1.day.ago, linked_at: 1.day.ago)
      android(first_authenticated_request_at: 1.day.ago, linked_at: nil)
      android(first_authenticated_request_at: 2.days.ago, linked_at: 2.days.ago)
      android(first_authenticated_request_at: 40.days.ago, linked_at: nil) # outside the window

      timeline = result[:health_timeline]
      expect(timeline.size).to eq(2)
      expect(timeline.first[:observed_authenticated_installations]).to eq(2)
      expect(timeline.first[:linked_installations]).to eq(1)
      expect(timeline.first[:link_rate].value).to eq(50.0)
      expect(timeline.last[:link_rate].value).to eq(100.0)
      expect(timeline.first[:date] > timeline.last[:date]).to be(true)
    end
  end

  describe "provenance and pipeline" do
    it "reports where the record came from without calling it tracking health" do
      android(source: "register")
      android(source: "backfill_device_token")

      provenance = result[:installation_provenance]
      expect(provenance[:registered_live]).to eq(1)
      expect(provenance[:backfilled]).to eq(1)
      expect(provenance[:coverage].value).to eq(50.0)
    end

    it "keeps analytics events out of the installation counts" do
      android
      android_event(occurred_at: 1.hour.ago)

      expect(result[:overview][:total_installations]).to eq(1)
      expect(result[:analytics_pipeline][:android_events_total]).to eq(1)
      expect(result[:analytics_pipeline][:android_events_7d]).to eq(1)
    end

    it "counts installs that reported a session" do
      android(last_session_at: Time.current)
      android(last_session_at: nil)

      expect(result[:analytics_pipeline][:installations_with_session]).to eq(1)
    end
  end

  describe "operational health" do
    it "reports unknown instead of healthy when there is no signal" do
      component = result[:operational_health].find { |c| c[:key] == :tracking }
      expect(component[:status]).to eq("unknown")
    end

    it "flags reconciliation as critical when observed authenticated installs are mostly unlinked" do
      8.times { android(first_authenticated_request_at: 1.hour.ago, user: nil) }
      2.times do
        android(user: create(:user), first_authenticated_request_at: 1.hour.ago, linked_at: 1.hour.ago)
      end

      component = result[:operational_health].find { |c| c[:key] == :reconciliation }
      expect(component[:status]).to eq("critical")
      expect(component[:detail]).to include("2 de 10")
    end

    it "reports reconciliation as ok at a full link rate" do
      3.times do
        android(user: create(:user), first_authenticated_request_at: 1.hour.ago, linked_at: 1.hour.ago)
      end

      component = result[:operational_health].find { |c| c[:key] == :reconciliation }
      expect(component[:status]).to eq("ok")
    end

    it "exposes one entry per ecosystem component" do
      expect(result[:operational_health].map { |c| c[:key] })
        .to eq(%i[tracking reconciliation push analytics webhooks device_tokens])
    end
  end

  describe "user funnel" do
    it "keys every step on linked users, never on installations" do
      user = create(:user)
      android(user: user)
      android(user: user) # same user, two installs
      user.workout_plans.create!(active: true)

      funnel = result[:user_funnel]
      expect(funnel.first[:label]).to eq("Usuários Android vinculados")
      expect(funnel.first[:count]).to eq(1)
      expect(funnel.find { |s| s[:label] == "Criou treino" }[:count]).to eq(1)
      expect(funnel.map { |s| s[:conversion].denominator }.uniq).to eq([ 1 ])
    end
  end

  describe "google play placeholder" do
    it "never invents an official install count" do
      expect(result[:google_play]).to eq(
        configured: false, official_installs: nil, last_synced_at: nil, source: nil
      )
    end
  end

  describe "payload hygiene" do
    it "exposes no installation_id nor user identifier" do
      android(installation_id: "secret-install-id", user: create(:user, email: "leak@example.com"))

      json = result.to_json
      expect(json).not_to include("secret-install-id")
      expect(json).not_to include("leak@example.com")
      expect(json).not_to include("installation_id")
    end

    it "declares the definitions the UI renders" do
      expect(result[:definitions]).to include(
        reconciliation_rate: "linked_at / first_authenticated_request_at",
        timeline_days: described_class::TIMELINE_DAYS
      )
      expect(result[:source]).to eq("app_installations")
    end
  end
end
