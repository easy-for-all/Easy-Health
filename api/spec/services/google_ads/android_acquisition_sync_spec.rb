require "rails_helper"

RSpec.describe GoogleAds::AndroidAcquisitionSync do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.parse("2026-08-13 12:00:00")) { example.run } }

  CAMPAIGN = "9911223344".freeze
  INSTALL_ACTION = "555001".freeze
  SIGNUP_ACTION = "555002".freeze
  OTHER_ACTION = "555999".freeze

  SYNC_ENV = {
    "GOOGLE_ADS_DEVELOPER_TOKEN" => "dev-token",
    "GOOGLE_ADS_CLIENT_ID" => "client-id",
    "GOOGLE_ADS_CLIENT_SECRET" => "client-secret",
    "GOOGLE_ADS_REFRESH_TOKEN" => "refresh-token",
    "GOOGLE_ADS_CUSTOMER_ID_EASYHEALTH" => "1234567890",
    "GOOGLE_ADS_ANDROID_CAMPAIGN_ID" => CAMPAIGN,
    "GOOGLE_ADS_INSTALL_CONVERSION_ACTION_ID" => INSTALL_ACTION,
    "GOOGLE_ADS_SIGNUP_CONVERSION_ACTION_ID" => SIGNUP_ACTION
  }.freeze

  # A client double that answers the performance query and the conversion query
  # by looking at which fields the GAQL asks for.
  class FakeAdsClient
    attr_reader :queries

    def initialize(performance: [], conversions: [])
      @performance = performance
      @conversions = conversions
      @queries = []
    end

    def search(query)
      @queries << query
      query.include?("segments.conversion_action") ? @conversions : @performance
    end
  end

  def performance_row(date:, cost_micros:, impressions: 100, clicks: 10, campaign_id: CAMPAIGN)
    {
      "campaign" => { "id" => campaign_id, "name" => "EasyHealth Android" },
      "segments" => { "date" => date },
      "metrics" => {
        "impressions" => impressions.to_s,
        "clicks" => clicks.to_s,
        "costMicros" => cost_micros.to_s
      }
    }
  end

  def conversion_row(date:, action_id:, conversions:, all_conversions: nil, campaign_id: CAMPAIGN)
    {
      "campaign" => { "id" => campaign_id, "name" => "EasyHealth Android" },
      "segments" => {
        "date" => date,
        "conversionAction" => "customers/1234567890/conversionActions/#{action_id}",
        "conversionActionName" => "action #{action_id}"
      },
      "metrics" => {
        "conversions" => conversions,
        "allConversions" => all_conversions || conversions
      }
    }
  end

  def run_sync(client, days: 7)
    with_env(SYNC_ENV) { described_class.new(days: days, client: client).call }
  end

  describe "window" do
    it "covers today plus the 7 previous days — 8 dates including today" do
      with_env(SYNC_ENV) do
        sync = described_class.new(client: FakeAdsClient.new)

        expect(sync.end_date).to eq(Date.new(2026, 8, 13))
        expect(sync.start_date).to eq(Date.new(2026, 8, 6))
        expect((sync.end_date - sync.start_date).to_i + 1).to eq(8)
      end
    end
  end

  describe "cost" do
    it "converts cost_micros to BRL without losing precision" do
      client = FakeAdsClient.new(performance: [ performance_row(date: "2026-08-12", cost_micros: 12_345_678) ])
      run_sync(client)

      record = GoogleAdsDailyMetric.find_by(date: Date.new(2026, 8, 12))
      expect(record.cost_micros).to eq(12_345_678)
      expect(record.cost_brl).to eq(12.345678)
    end

    it "never multiplies daily cost by the number of conversion actions" do
      client = FakeAdsClient.new(
        performance: [ performance_row(date: "2026-08-12", cost_micros: 50_000_000) ],
        conversions: [
          conversion_row(date: "2026-08-12", action_id: INSTALL_ACTION, conversions: 4.0),
          conversion_row(date: "2026-08-12", action_id: SIGNUP_ACTION, conversions: 2.0),
          conversion_row(date: "2026-08-12", action_id: OTHER_ACTION, conversions: 7.0)
        ]
      )
      run_sync(client)

      expect(GoogleAdsDailyMetric.sum(:cost_micros)).to eq(50_000_000)
    end

    it "asks for cost only in the query that has no conversion segment" do
      client = FakeAdsClient.new
      run_sync(client)

      cost_queries = client.queries.select { |q| q.include?("metrics.cost_micros") }
      expect(cost_queries.size).to eq(1)
      expect(cost_queries.first).not_to include("segments.conversion_action")
    end
  end

  describe "conversion actions" do
    it "maps the configured actions to installs and sign_ups, ignoring the rest" do
      client = FakeAdsClient.new(
        performance: [ performance_row(date: "2026-08-12", cost_micros: 10_000_000) ],
        conversions: [
          conversion_row(date: "2026-08-12", action_id: INSTALL_ACTION, conversions: 4.5),
          conversion_row(date: "2026-08-12", action_id: SIGNUP_ACTION, conversions: 2.25),
          conversion_row(date: "2026-08-12", action_id: OTHER_ACTION, conversions: 99.0)
        ]
      )
      run_sync(client)

      record = GoogleAdsDailyMetric.find_by(date: Date.new(2026, 8, 12))
      expect(record.installs).to eq(BigDecimal("4.5"))
      expect(record.sign_ups).to eq(BigDecimal("2.25"))
    end

    it "keeps fractional conversions instead of truncating them to integers" do
      client = FakeAdsClient.new(
        performance: [ performance_row(date: "2026-08-12", cost_micros: 1_000_000) ],
        conversions: [ conversion_row(date: "2026-08-12", action_id: INSTALL_ACTION, conversions: 0.83) ]
      )
      run_sync(client)

      expect(GoogleAdsDailyMetric.find_by(date: Date.new(2026, 8, 12)).installs).to eq(BigDecimal("0.83"))
    end

    it "reports the all_conversions divergence without changing the KPIs" do
      client = FakeAdsClient.new(
        performance: [ performance_row(date: "2026-08-12", cost_micros: 1_000_000) ],
        conversions: [
          conversion_row(date: "2026-08-12", action_id: SIGNUP_ACTION, conversions: 2.0, all_conversions: 5.0)
        ]
      )
      result = run_sync(client)

      expect(result.sign_ups).to eq(BigDecimal("2.0"))
      expect(result.conversion_column_divergence[:sign_ups]).to eq(3.0)
    end
  end

  describe "campaign isolation" do
    it "never blends rows from another campaign" do
      client = FakeAdsClient.new(
        performance: [
          performance_row(date: "2026-08-12", cost_micros: 10_000_000),
          performance_row(date: "2026-08-12", cost_micros: 99_000_000, campaign_id: "7777777777")
        ],
        conversions: [
          conversion_row(date: "2026-08-12", action_id: INSTALL_ACTION, conversions: 3.0),
          conversion_row(date: "2026-08-12", action_id: INSTALL_ACTION, conversions: 50.0,
                         campaign_id: "7777777777")
        ]
      )
      run_sync(client)

      expect(GoogleAdsDailyMetric.count).to eq(1)
      record = GoogleAdsDailyMetric.first
      expect(record.campaign_id).to eq(CAMPAIGN)
      expect(record.cost_micros).to eq(10_000_000)
      expect(record.installs).to eq(BigDecimal("3.0"))
    end
  end

  describe "idempotency" do
    it "upserts instead of duplicating when the same window is synced twice" do
      rows = {
        performance: [ performance_row(date: "2026-08-12", cost_micros: 10_000_000) ],
        conversions: [ conversion_row(date: "2026-08-12", action_id: INSTALL_ACTION, conversions: 3.0) ]
      }

      run_sync(FakeAdsClient.new(**rows))
      run_sync(FakeAdsClient.new(**rows))

      expect(GoogleAdsDailyMetric.count).to eq(1)
    end

    it "overwrites a day with Google's revised attribution" do
      run_sync(FakeAdsClient.new(
        performance: [ performance_row(date: "2026-08-12", cost_micros: 10_000_000) ],
        conversions: [ conversion_row(date: "2026-08-12", action_id: SIGNUP_ACTION, conversions: 1.0) ]
      ))
      run_sync(FakeAdsClient.new(
        performance: [ performance_row(date: "2026-08-12", cost_micros: 11_000_000) ],
        conversions: [ conversion_row(date: "2026-08-12", action_id: SIGNUP_ACTION, conversions: 3.0) ]
      ))

      record = GoogleAdsDailyMetric.find_by(date: Date.new(2026, 8, 12))
      expect(record.cost_micros).to eq(11_000_000)
      expect(record.sign_ups).to eq(BigDecimal("3.0"))
    end
  end

  describe "not configured" do
    it "returns not_configured and writes nothing" do
      with_env(SYNC_ENV.merge("GOOGLE_ADS_ANDROID_CAMPAIGN_ID" => nil)) do
        result = described_class.new(client: FakeAdsClient.new).call

        expect(result.status).to eq("not_configured")
        expect(result.missing).to include("GOOGLE_ADS_ANDROID_CAMPAIGN_ID")
        expect(GoogleAdsDailyMetric.count).to eq(0)
      end
    end
  end

  describe "API failure" do
    it "preserves the previous snapshot instead of zeroing it" do
      run_sync(FakeAdsClient.new(
        performance: [ performance_row(date: "2026-08-12", cost_micros: 10_000_000) ],
        conversions: [ conversion_row(date: "2026-08-12", action_id: INSTALL_ACTION, conversions: 3.0) ]
      ))

      failing = instance_double(GoogleAds::Client)
      allow(failing).to receive(:search).and_raise(GoogleAds::Client::Error.new("boom", status: 500))

      expect { run_sync(failing) }.to raise_error(GoogleAds::Client::Error)

      record = GoogleAdsDailyMetric.find_by(date: Date.new(2026, 8, 12))
      expect(record.cost_micros).to eq(10_000_000)
      expect(record.installs).to eq(BigDecimal("3.0"))
    end
  end
end
