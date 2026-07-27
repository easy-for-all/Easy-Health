require "rails_helper"
require Rails.root.join("db/migrate/20260727120001_create_observability_check_results").to_s

RSpec.describe Observability::BiViews do
  def query(view)
    ActiveRecord::Base.connection.select_all("SELECT * FROM #{view} LIMIT 5").to_a
  end

  it "declares the five documented views" do
    expect(described_class.view_names).to match_array(%w[
      bi_observability_android_build_daily
      bi_observability_daily
      bi_observability_google_auth_daily
      bi_observability_heartbeats
      bi_observability_incidents
    ])
  end

  it "creates every view in the database" do
    # db/schema.rb cannot carry views, so the suite applies them in
    # before(:suite). This asserts that hook actually worked.
    expect(described_class.verify!).to match_array(described_class.view_names)
  end

  it "is idempotent" do
    expect { described_class.apply! }.not_to raise_error
    expect(described_class.verify!.size).to eq(5)
  end

  it "drops managed views and recreates them" do
    expect(described_class.drop!).to match_array(described_class.view_names)
    expect(described_class.verify!).to be_empty
    expect(described_class.apply!).to match_array(described_class.view_names)
  ensure
    described_class.apply!
  end

  it "uses the same prefix-only drop behavior needed by table rollbacks" do
    ActiveRecord::Base.connection.execute("CREATE VIEW bi_observability_temp_spec AS SELECT 1 AS value")

    CreateObservabilityCheckResults.new.send(:drop_observability_bi_views)

    expect(described_class.verify!).to be_empty
    expect(
      ActiveRecord::Base.connection.select_value(<<~SQL.squish)
        SELECT viewname FROM pg_views
        WHERE schemaname = ANY (current_schemas(false))
          AND viewname = 'bi_observability_temp_spec'
      SQL
    ).to be_nil
  ensure
    described_class.apply!
  end

  describe "querying with no data" do
    it "returns empty rather than raising" do
      described_class.view_names.each do |view|
        expect { query(view) }.not_to raise_error
      end
    end
  end

  describe "division by zero" do
    it "returns NULL, not 0, for a build with no installations to divide by" do
      # A build that only appears in the events table has no install denominator.
      ProductAnalyticsEvent.create!(
        event_name: "google_auth_failed", event_version: 1,
        occurred_at: Time.current, received_at: Time.current,
        platform: "android", app_surface: "unknown", environment: "test",
        app_version: "9.9.9", build_number: "999", source: "easyhealth_backend",
        properties: { "auth_flow" => "native", "error_code" => "invalid_token" }
      )

      row = query("bi_observability_android_build_daily").find { |r| r["app_build"] == "999" }

      expect(row).to be_present
      expect(row["installations"]).to eq(0)
      expect(row["registration_conversion_rate"]).to be_nil
      expect(row["linkage_rate"]).to be_nil
    end

    it "computes a rate when there is a denominator" do
      user = create(:user)
      AppInstallation.create!(installation_id: SecureRandom.uuid, platform: "android",
                              app_build: "51", app_version: "1.0.51", user: user)
      AppInstallation.create!(installation_id: SecureRandom.uuid, platform: "android",
                              app_build: "51", app_version: "1.0.51")

      row = query("bi_observability_android_build_daily").find { |r| r["app_build"] == "51" }

      expect(row["installations"]).to eq(2)
      expect(row["linked_installations"]).to eq(1)
      expect(row["linkage_rate"].to_f).to eq(0.5)
    end
  end

  describe "bi_observability_heartbeats" do
    it "mirrors the model's status logic, including the fresh-process case" do
      ObservabilityHeartbeat.create!(key: "fresh", category: "job", expected_interval_seconds: 3600)
      ObservabilityHeartbeat.create!(key: "late", category: "cron", expected_interval_seconds: 3600,
                                     last_succeeded_at: 5.hours.ago)
      ObservabilityHeartbeat.create!(key: "ok", category: "job", expected_interval_seconds: 3600,
                                     last_succeeded_at: 5.minutes.ago)

      rows = query("bi_observability_heartbeats").index_by { |r| r["key"] }

      expect(rows["fresh"]["calculated_status"]).to eq("insufficient_data")
      expect(rows["fresh"]["seconds_since_success"]).to be_nil
      expect(rows["late"]["calculated_status"]).to eq("critical")
      expect(rows["ok"]["calculated_status"]).to eq("healthy")
    end
  end

  describe "bi_observability_incidents" do
    it "reports duration for an open incident using now()" do
      ObservabilityIncident.create!(
        fingerprint: SecureRandom.hex(8), source: "internal_check",
        check_key: "x", title: "aberto", severity: "warning", status: "open",
        first_detected_at: 30.minutes.ago, last_detected_at: Time.current
      )

      row = query("bi_observability_incidents").first
      expect(row["is_resolved"]).to be(false)
      expect(row["duration_minutes"].to_f).to be_within(2).of(30)
    end
  end

  describe "bi_observability_google_auth_daily" do
    it "separates the expected consent_required from the anomalous one" do
      base = {
        event_name: "google_auth_failed", event_version: 1,
        occurred_at: Time.current, received_at: Time.current,
        platform: "android", app_surface: "unknown", environment: "test",
        app_version: "1.0.51", build_number: "51", source: "easyhealth_backend"
      }

      ProductAnalyticsEvent.create!(base.merge(properties: {
        "auth_flow" => "native", "error_code" => "consent_required",
        "auth_intent" => "login", "terms_accepted" => false
      }))
      ProductAnalyticsEvent.create!(base.merge(properties: {
        "auth_flow" => "native", "error_code" => "consent_required",
        "auth_intent" => "sign_up", "terms_accepted" => true
      }))

      row = query("bi_observability_google_auth_daily").first

      expect(row["consent_required"]).to eq(2)
      # Only one of them is a defect.
      expect(row["consent_required_with_terms"]).to eq(1)
      expect(row["error_rate"].to_f).to eq(1.0)
    end
  end
end
