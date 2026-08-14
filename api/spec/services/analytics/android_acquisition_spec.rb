require "rails_helper"

RSpec.describe Analytics::AndroidAcquisition do
  include ActiveSupport::Testing::TimeHelpers

  # Frozen: every cohort cut and maturity check depends on "today".
  around { |example| travel_to(Time.zone.parse("2026-08-13 12:00:00")) { example.run } }

  ACQ_CAMPAIGN = "9911223344".freeze

  ACQ_ENV = {
    "GOOGLE_ADS_DEVELOPER_TOKEN" => "dev-token",
    "GOOGLE_ADS_CLIENT_ID" => "client-id",
    "GOOGLE_ADS_CLIENT_SECRET" => "client-secret",
    "GOOGLE_ADS_REFRESH_TOKEN" => "refresh-token",
    "GOOGLE_ADS_CUSTOMER_ID_EASYHEALTH" => "1234567890",
    "GOOGLE_ADS_ANDROID_CAMPAIGN_ID" => ACQ_CAMPAIGN,
    "GOOGLE_ADS_INSTALL_CONVERSION_ACTION_ID" => "555001",
    "GOOGLE_ADS_SIGNUP_CONVERSION_ACTION_ID" => "555002"
  }.freeze

  def ads_row(date:, campaign_id: ACQ_CAMPAIGN, cost_micros: 0, installs: 0, sign_ups: 0,
              impressions: 0, clicks: 0, synced_at: Time.current)
    GoogleAdsDailyMetric.create!(
      date: date, campaign_id: campaign_id, campaign_name: "EasyHealth Android",
      cost_micros: cost_micros, installs: installs, sign_ups: sign_ups,
      impressions: impressions, clicks: clicks, synced_at: synced_at
    )
  end

  # An external Android account created at a given local (America/Sao_Paulo)
  # time, optionally with a plan / a started session / a completed session.
  def android_user(created_at:, plan: false, started: false, completed: false, email: nil)
    user = create(:user, signup_source: "android", created_at: created_at)
    user.update_column(:email, email) if email

    WorkoutPlan.create!(user: user, active: true) if plan

    if started
      WorkoutSession.create!(user: user, status: "in_progress", started_at: created_at + 1.hour,
                             completion_status: "abandoned")
    end

    if completed
      WorkoutSession.create!(user: user, status: "completed", started_at: created_at + 2.hours,
                             completed_at: created_at + 3.hours, duration_minutes: 30,
                             completion_status: "completed")
    end

    user
  end

  def result(**args)
    with_env(ACQ_ENV) { described_class.new(**args).call }
  end

  describe "date range" do
    it "defaults to the last 7 days ending today" do
      payload = result

      expect(payload[:filters][:period]).to eq("7d")
      expect(payload[:filters][:start_date]).to eq("2026-08-07")
      expect(payload[:filters][:end_date]).to eq("2026-08-13")
    end

    it "accepts a custom range" do
      payload = result(period: "custom", start_date: "2026-08-01", end_date: "2026-08-05")

      expect(payload[:filters][:start_date]).to eq("2026-08-01")
      expect(payload[:filters][:end_date]).to eq("2026-08-05")
    end

    it "rejects an inverted custom range" do
      expect { result(period: "custom", start_date: "2026-08-10", end_date: "2026-08-01") }
        .to raise_error(described_class::InvalidRange)
    end

    it "rejects a malformed custom range" do
      expect { result(period: "custom", start_date: "ontem", end_date: "2026-08-01") }
        .to raise_error(described_class::InvalidRange)
    end

    it "rejects a range longer than the maximum window" do
      expect { result(period: "custom", start_date: "2020-01-01", end_date: "2026-08-01") }
        .to raise_error(described_class::InvalidRange)
    end
  end

  describe "google ads block" do
    it "sums the cached rows of the configured campaign only" do
      ads_row(date: Date.new(2026, 8, 12), cost_micros: 30_000_000, installs: 10, sign_ups: 4,
              impressions: 1000, clicks: 100)
      ads_row(date: Date.new(2026, 8, 12), campaign_id: "7777777777", cost_micros: 99_000_000,
              installs: 50, sign_ups: 40)

      ads = result[:ads]

      expect(ads[:cost_brl]).to eq(30.0)
      expect(ads[:installs]).to eq(10.0)
      expect(ads[:sign_ups]).to eq(4.0)
      expect(ads[:impressions]).to eq(1000)
      expect(ads[:clicks]).to eq(100)
    end

    it "computes CPI, CPA and install→signup inside the Ads universe" do
      ads_row(date: Date.new(2026, 8, 12), cost_micros: 40_000_000, installs: 8, sign_ups: 2)

      ads = result[:ads]

      expect(ads[:cpi_brl]).to eq(5.0)
      expect(ads[:cpa_signup_brl]).to eq(20.0)
      expect(ads[:install_to_signup][:value]).to eq(25.0)
    end

    it "returns nil (not zero) for CPI when there are no installs" do
      ads_row(date: Date.new(2026, 8, 12), cost_micros: 40_000_000, installs: 0, sign_ups: 0)

      ads = result[:ads]

      expect(ads[:cpi_brl]).to be_nil
      expect(ads[:cpa_signup_brl]).to be_nil
      expect(ads[:install_to_signup]).to be_nil
    end

    it "treats zero attributed sign_ups on a spending day as a legitimate zero" do
      ads_row(date: Date.new(2026, 8, 12), cost_micros: 40_000_000, installs: 5, sign_ups: 0)

      payload = result

      expect(payload[:ads][:sign_ups]).to eq(0.0)
      expect(payload[:sync][:status]).to eq("ok")
    end

    it "never exposes a rate that crosses the two universes" do
      ads_row(date: Date.new(2026, 8, 12), cost_micros: 40_000_000, installs: 8, sign_ups: 2)
      android_user(created_at: Time.zone.parse("2026-08-12 10:00:00"))

      payload = result

      expect(payload[:ads].keys).not_to include(:install_to_account, :cost_per_account)
      expect(payload[:easyhealth].keys).not_to include(:install_to_account)
    end
  end

  describe "easyhealth cohort" do
    it "counts only external android accounts" do
      android_user(created_at: Time.zone.parse("2026-08-12 10:00:00"))
      android_user(created_at: Time.zone.parse("2026-08-12 11:00:00"),
                   email: "robot@cloudtestlabaccounts.com")
      android_user(created_at: Time.zone.parse("2026-08-12 11:30:00"), email: "hello@easyhealth.art")
      create(:user, signup_source: "web", created_at: Time.zone.parse("2026-08-12 10:00:00"))

      expect(result[:easyhealth][:accounts]).to eq(1)
    end

    it "follows the same accounts through the funnel, not loose daily events" do
      android_user(created_at: Time.zone.parse("2026-08-10 10:00:00"), plan: true, started: true,
                   completed: true)
      android_user(created_at: Time.zone.parse("2026-08-10 11:00:00"), plan: true, started: true)
      android_user(created_at: Time.zone.parse("2026-08-10 12:00:00"), plan: true)
      android_user(created_at: Time.zone.parse("2026-08-10 13:00:00"))

      eh = result[:easyhealth]

      expect(eh[:accounts]).to eq(4)
      expect(eh[:created_workout]).to eq(3)
      expect(eh[:started_workout]).to eq(2)
      expect(eh[:completed_workout]).to eq(1)
      expect(eh[:account_to_created][:value]).to eq(75.0)
    end

    it "cuts the cohort day in the reporting timezone, not in UTC" do
      # 23:30 in São Paulo on the 11th is 02:30Z on the 12th.
      android_user(created_at: Time.zone.parse("2026-08-12 02:30:00"))

      dates = result[:daily].map { |row| row[:date] }
      expect(dates).to include("2026-08-11")
      expect(dates).not_to include("2026-08-12")
    end

    it "flags a cohort that has not had time to train yet" do
      android_user(created_at: Time.zone.parse("2026-08-13 09:00:00"))

      payload = result(period: "today")
      expect(payload[:easyhealth][:cohort_maturity]).to eq("immature")

      payload = result(period: "yesterday")
      expect(payload[:easyhealth][:cohort_maturity]).to eq("mature")
    end

    it "reports no_coverage instead of 0% when there is nothing to divide by" do
      eh = result[:easyhealth]

      expect(eh[:account_to_created][:status]).to eq("no_coverage")
      expect(eh[:created_to_started][:status]).to eq("no_coverage")
    end
  end

  describe "daily table" do
    it "puts both universes on the same line, most recent first" do
      ads_row(date: Date.new(2026, 8, 12), cost_micros: 20_000_000, installs: 5, sign_ups: 2)
      ads_row(date: Date.new(2026, 8, 11), cost_micros: 10_000_000, installs: 3, sign_ups: 1)
      android_user(created_at: Time.zone.parse("2026-08-12 10:00:00"), plan: true)

      rows = result[:daily]

      expect(rows.first[:date]).to eq("2026-08-12")
      expect(rows.first[:ads][:cost_brl]).to eq(20.0)
      expect(rows.first[:easyhealth][:accounts]).to eq(1)
      expect(rows.second[:date]).to eq("2026-08-11")
      expect(rows.second[:easyhealth][:accounts]).to eq(0)
    end

    it "keeps the product line when Google has no row for that day" do
      android_user(created_at: Time.zone.parse("2026-08-12 10:00:00"))

      row = result[:daily].find { |item| item[:date] == "2026-08-12" }

      expect(row[:ads]).to be_nil
      expect(row[:easyhealth][:accounts]).to eq(1)
    end
  end

  describe "sync status" do
    it "reports not_configured without credentials, and still serves the product block" do
      android_user(created_at: Time.zone.parse("2026-08-12 10:00:00"))

      payload = with_env(ACQ_ENV.merge("GOOGLE_ADS_REFRESH_TOKEN" => nil)) { described_class.new.call }

      expect(payload[:sync][:status]).to eq("not_configured")
      expect(payload[:sync][:missing_configuration]).to include("GOOGLE_ADS_REFRESH_TOKEN")
      expect(payload[:easyhealth][:accounts]).to eq(1)
    end

    it "reports never_synced when the cache is empty" do
      expect(result[:sync][:status]).to eq("never_synced")
    end

    it "reports ok on a fresh cache" do
      ads_row(date: Date.new(2026, 8, 12), synced_at: 5.minutes.ago)

      expect(result[:sync][:status]).to eq("ok")
    end

    it "reports stale — not an outage — when the cache is merely old" do
      ads_row(date: Date.new(2026, 8, 12), synced_at: 6.hours.ago)

      payload = result

      expect(payload[:sync][:status]).to eq("stale")
      expect(payload[:sync][:label]).to eq("Dados Google Ads desatualizados")
    end

    it "reports error only when the heartbeat has evidence of a failure, keeping the old data" do
      ads_row(date: Date.new(2026, 8, 12), cost_micros: 20_000_000, installs: 5, synced_at: 10.minutes.ago)
      ObservabilityHeartbeat.create!(
        key: described_class::HEARTBEAT_KEY, category: "cron", expected_interval_seconds: 3600,
        last_succeeded_at: 3.hours.ago, last_failed_at: 5.minutes.ago, last_error_code: "GoogleAds::Client::Error"
      )

      payload = result

      expect(payload[:sync][:status]).to eq("error")
      expect(payload[:sync][:last_error_code]).to eq("GoogleAds::Client::Error")
      expect(payload[:ads][:cost_brl]).to eq(20.0)
      expect(payload[:ads][:installs]).to eq(5.0)
    end
  end

  describe "payload hygiene" do
    it "never leaks a credential" do
      ads_row(date: Date.new(2026, 8, 12), cost_micros: 20_000_000)

      json = result.to_json

      expect(json).not_to include("dev-token")
      expect(json).not_to include("refresh-token")
      expect(json).not_to include("client-secret")
    end
  end
end
