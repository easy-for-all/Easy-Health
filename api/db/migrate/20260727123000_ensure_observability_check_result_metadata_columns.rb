class EnsureObservabilityCheckResultMetadataColumns < ActiveRecord::Migration[8.1]
  TABLE = :observability_check_results

  def up
    return unless table_exists?(TABLE)

    ensure_environment_column
    ensure_severity_column
    ensure_unit_column
    add_column(TABLE, :definition, :text) unless column_exists?(TABLE, :definition)
  end

  def down
    # Intentionally irreversible: these columns are part of the canonical
    # create-table migration for fresh databases. This migration only repairs
    # databases that applied an earlier draft before the metadata columns existed.
  end

  private

  def ensure_environment_column
    add_column(TABLE, :environment, :string) unless column_exists?(TABLE, :environment)

    execute <<~SQL.squish
      UPDATE #{TABLE}
      SET environment = 'production'
      WHERE environment IS NULL OR environment = ''
    SQL

    change_column_default TABLE, :environment, "production"
    change_column_null TABLE, :environment, false
  end

  def ensure_severity_column
    add_column(TABLE, :severity, :string) unless column_exists?(TABLE, :severity)

    execute <<~SQL.squish
      UPDATE #{TABLE}
      SET severity = CASE
        WHEN status = 'critical' THEN 'critical'
        WHEN status = 'warning' THEN 'warning'
        ELSE 'info'
      END
      WHERE severity IS NULL OR severity = ''
    SQL

    change_column_default TABLE, :severity, "info"
    change_column_null TABLE, :severity, false
  end

  def ensure_unit_column
    add_column(TABLE, :unit, :string) unless column_exists?(TABLE, :unit)

    execute <<~SQL.squish
      UPDATE #{TABLE}
      SET unit = #{unit_case_sql}
      WHERE unit IS NULL OR unit = ''
    SQL

    change_column_default TABLE, :unit, "ratio"
    change_column_null TABLE, :unit, false
  end

  def unit_case_sql
    <<~SQL.squish
      CASE
        WHEN check_key IN ('api_latency_p95', 'replica_refresh_stale')
          OR check_key LIKE 'stale_heartbeat:%'
          THEN 'seconds'
        WHEN check_key IN (
          'authenticated_without_installation_link',
          'google_auth_consent_anomaly',
          'repeated_job_failure',
          'make_delivery_backlog',
          'stripe_webhook_failure',
          'android_analytics_ingestion_stale'
        )
          THEN 'count'
        ELSE 'ratio'
      END
    SQL
  end
end
