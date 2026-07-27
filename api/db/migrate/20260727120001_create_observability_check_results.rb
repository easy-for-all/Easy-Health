class CreateObservabilityCheckResults < ActiveRecord::Migration[8.1]
  def up
    create_table :observability_check_results do |t|
      t.string :check_key, null: false
      # healthy | warning | critical | insufficient_data
      t.string :status, null: false
      # Carried on the row (not derived at read time) so the BI replica, which
      # is a restore of production into another database, still reports the
      # environment the measurement was actually taken in.
      t.string :environment, null: false, default: "production"
      # info | warning | critical
      t.string :severity, null: false, default: "info"

      t.datetime :window_started_at
      t.datetime :window_ended_at

      # NULL — never 0 — when there was not enough sample to measure. A zero
      # here would read as "0% conversion", which is a different claim.
      t.decimal :current_value, precision: 12, scale: 4
      t.decimal :reference_value, precision: 12, scale: 4
      t.decimal :threshold_value, precision: 12, scale: 4
      t.integer :sample_size

      # ratio | count | seconds. Persisted because the admin panel formats the
      # value from it — a count rendered as a percentage is a wrong number, not
      # a cosmetic issue.
      t.string :unit, null: false, default: "ratio"

      t.jsonb :dimensions, null: false, default: {}
      t.text :explanation
      # How the value was computed, shown next to it so the panel never presents
      # a number without saying what it measures.
      t.text :definition

      t.datetime :checked_at, null: false

      t.datetime :created_at, null: false
    end

    add_index :observability_check_results, [ :check_key, :checked_at ]
    add_index :observability_check_results, [ :status, :checked_at ]
    add_index :observability_check_results, :checked_at
  end

  def down
    drop_observability_bi_views
    drop_table :observability_check_results, if_exists: true
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
