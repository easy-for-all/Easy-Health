require "rails_helper"
require Rails.root.join("db/migrate/20260727123000_ensure_observability_check_result_metadata_columns").to_s

RSpec.describe EnsureObservabilityCheckResultMetadataColumns do
  let(:connection) { ActiveRecord::Base.connection }

  def reset_observability_schema_cache!
    connection.schema_cache.clear!
    ObservabilityCheckResult.reset_column_information
  end

  def remove_metadata_columns!
    Observability::BiViews.drop!

    %i[definition unit severity environment].each do |column|
      connection.remove_column :observability_check_results, column if connection.column_exists?(:observability_check_results, column)
    end

    reset_observability_schema_cache!
  end

  def insert_legacy_result(check_key:, status:)
    now = connection.quote(Time.current)
    quoted_key = connection.quote(check_key)
    quoted_status = connection.quote(status)

    connection.execute <<~SQL.squish
      INSERT INTO observability_check_results
        (check_key, status, current_value, checked_at, created_at)
      VALUES
        (#{quoted_key}, #{quoted_status}, 1.0, #{now}, #{now})
    SQL
  end

  def observability_views_ready?
    connection.table_exists?(:observability_check_results) &&
      connection.table_exists?(:observability_heartbeats) &&
      connection.table_exists?(:observability_incidents) &&
      connection.column_exists?(:observability_check_results, :environment)
  end

  after do
    reset_observability_schema_cache!
    Observability::BiViews.apply! if observability_views_ready?
  end

  it "adds and backfills metadata columns on a legacy table, and can run twice" do
    remove_metadata_columns!

    insert_legacy_result(check_key: "api_latency_p95", status: "warning")
    insert_legacy_result(check_key: "make_delivery_backlog", status: "critical")
    insert_legacy_result(check_key: "android_registration_conversion", status: "healthy")

    described_class.new.up
    expect { described_class.new.up }.not_to raise_error

    reset_observability_schema_cache!

    columns = connection.columns(:observability_check_results).index_by(&:name)
    expect(columns["environment"].default).to eq("production")
    expect(columns["environment"].null).to be(false)
    expect(columns["severity"].default).to eq("info")
    expect(columns["severity"].null).to be(false)
    expect(columns["unit"].default).to eq("ratio")
    expect(columns["unit"].null).to be(false)
    expect(columns["definition"].type).to eq(:text)

    rows = connection
           .select_all("SELECT check_key, environment, severity, unit, definition FROM observability_check_results")
           .to_a
           .index_by { |row| row["check_key"] }

    expect(rows["api_latency_p95"]).to include("environment" => "production", "severity" => "warning", "unit" => "seconds")
    expect(rows["make_delivery_backlog"]).to include("environment" => "production", "severity" => "critical", "unit" => "count")
    expect(rows["android_registration_conversion"]).to include("environment" => "production", "severity" => "info", "unit" => "ratio")
    expect(rows.values.map { |row| row["definition"] }).to all(be_nil)
  end
end
