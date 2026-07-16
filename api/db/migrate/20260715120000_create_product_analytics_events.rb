class CreateProductAnalyticsEvents < ActiveRecord::Migration[8.1]
  # Auditable product analytics events — the single source of truth for the
  # Admin dashboard funnels, activation, retention and platform comparison.
  # Distinct from user_events (Make/relationship) and onboarding_events (legacy
  # funnel), which are left untouched.
  def change
    create_table :product_analytics_events do |t|
      t.string   :event_name,   null: false
      t.integer  :event_version, null: false, default: 1
      t.datetime :occurred_at,  null: false
      t.datetime :received_at,  null: false

      # Identity — anonymous_id exists before login; user_id is set when known.
      t.string   :anonymous_id
      t.references :user, foreign_key: true, index: false
      t.string   :session_id

      # Context dimensions.
      t.string   :platform,     null: false, default: "unknown"
      t.string   :app_surface,  null: false, default: "unknown"
      t.string   :app_version
      t.string   :build_number
      t.string   :environment,  null: false, default: "production"
      t.string   :locale
      t.string   :timezone
      t.string   :source

      t.jsonb    :properties,   null: false, default: {}
      t.string   :idempotency_key

      t.timestamps
    end

    add_index :product_analytics_events, [ :event_name, :occurred_at ]
    add_index :product_analytics_events, [ :user_id, :occurred_at ]
    add_index :product_analytics_events, [ :platform, :occurred_at ]
    add_index :product_analytics_events, :anonymous_id
    add_index :product_analytics_events, :idempotency_key,
              unique: true, where: "idempotency_key IS NOT NULL"
  end
end
