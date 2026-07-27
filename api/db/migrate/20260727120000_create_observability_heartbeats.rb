class CreateObservabilityHeartbeats < ActiveRecord::Migration[8.1]
  def up
    create_table :observability_heartbeats do |t|
      # Stable process identifier, e.g. "relationship_daily_job".
      t.string :key, null: false
      # job | cron | integration | pipeline
      t.string :category, null: false, default: "job"
      # How often this process is expected to succeed. Drives the staleness
      # thresholds (1.5x warning, 2x critical).
      t.integer :expected_interval_seconds, null: false, default: 86_400

      t.datetime :last_started_at
      t.datetime :last_succeeded_at
      t.datetime :last_failed_at
      t.integer :last_duration_ms
      t.integer :consecutive_failures, null: false, default: 0
      t.string :last_error_code

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :observability_heartbeats, :key, unique: true
    add_index :observability_heartbeats, [ :category, :last_succeeded_at ]
  end

  def down
    drop_observability_bi_views
    drop_table :observability_heartbeats, if_exists: true
  end

  private

  def drop_observability_bi_views
    select_values(<<~SQL.squish).each do |view_name|
      SELECT quote_ident(schemaname) || '.' || quote_ident(viewname)
      FROM pg_views
      WHERE schemaname = ANY (current_schemas(false))
        AND LEFT(viewname, 17) = 'bi_observability_'
      ORDER BY viewname DESC
    SQL
      execute "DROP VIEW IF EXISTS #{view_name}"
    end
  end
end
