class CreateObservabilityIncidents < ActiveRecord::Migration[8.1]
  def up
    create_table :observability_incidents do |t|
      # Deterministic hash of source + check_key + relevant dimensions. Two
      # detections of the same problem must collapse into one incident.
      t.string :fingerprint, null: false
      # internal_check | grafana | sentry | manual
      t.string :source, null: false, default: "internal_check"
      t.string :check_key

      t.string :title, null: false
      t.text :description

      # warning | critical
      t.string :severity, null: false, default: "warning"
      # open | acknowledged | resolved
      t.string :status, null: false, default: "open"

      t.decimal :current_value, precision: 12, scale: 4
      t.decimal :threshold_value, precision: 12, scale: 4
      t.jsonb :dimensions, null: false, default: {}

      t.datetime :first_detected_at, null: false
      t.datetime :last_detected_at, null: false
      t.datetime :acknowledged_at
      t.string :acknowledged_by
      t.datetime :resolved_at
      t.string :resolved_by

      t.integer :occurrence_count, null: false, default: 1
      t.integer :notification_count, null: false, default: 0
      t.datetime :last_notified_at

      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    # Partial uniqueness: at most one live incident per fingerprint, while a
    # recurrence after resolution correctly opens a fresh one.
    add_index :observability_incidents, :fingerprint,
              unique: true,
              where: "status <> 'resolved'",
              name: "index_observability_incidents_active_fingerprint"

    add_index :observability_incidents, [ :status, :severity ]
    add_index :observability_incidents, :check_key
    add_index :observability_incidents, :first_detected_at
    add_index :observability_incidents, :resolved_at
  end

  def down
    drop_observability_bi_views
    drop_table :observability_incidents, if_exists: true
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
