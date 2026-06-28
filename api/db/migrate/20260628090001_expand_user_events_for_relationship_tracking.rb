class ExpandUserEventsForRelationshipTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :user_events, :occurred_at, :datetime
    add_column :user_events, :source, :string, default: "easyhealth_backend", null: false
    add_column :user_events, :payload_json, :jsonb, default: {}, null: false
    add_column :user_events, :idempotency_key, :string
    add_column :user_events, :make_delivery_status, :string, default: "disabled", null: false
    add_column :user_events, :make_last_attempt_at, :datetime
    add_column :user_events, :make_attempts_count, :integer, default: 0, null: false
    add_column :user_events, :make_last_error, :text
    add_column :user_events, :updated_at, :datetime

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE user_events
             SET occurred_at = created_at,
                 updated_at = created_at,
                 payload_json = COALESCE(metadata, '{}'::jsonb)
           WHERE occurred_at IS NULL OR updated_at IS NULL
        SQL
      end
    end

    change_column_null :user_events, :occurred_at, false
    change_column_null :user_events, :updated_at, false

    add_index :user_events, :idempotency_key
    add_index :user_events, [:user_id, :event_name, :idempotency_key],
      unique: true,
      where: "idempotency_key IS NOT NULL",
      name: "index_user_events_on_user_event_idempotency"
    add_index :user_events, [:make_delivery_status, :created_at],
      name: "index_user_events_on_make_status_and_created_at"
  end
end
