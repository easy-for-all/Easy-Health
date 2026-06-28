class ExpandUserEventsForRelationshipTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :user_events, :occurred_at, :datetime unless column_exists?(:user_events, :occurred_at)
    add_column :user_events, :source, :string, default: "easyhealth_backend", null: false unless column_exists?(:user_events, :source)
    add_column :user_events, :payload_json, :jsonb, default: {}, null: false unless column_exists?(:user_events, :payload_json)
    add_column :user_events, :idempotency_key, :string unless column_exists?(:user_events, :idempotency_key)
    add_column :user_events, :make_delivery_status, :string, default: "disabled", null: false unless column_exists?(:user_events, :make_delivery_status)
    add_column :user_events, :make_last_attempt_at, :datetime unless column_exists?(:user_events, :make_last_attempt_at)
    add_column :user_events, :make_attempts_count, :integer, default: 0, null: false unless column_exists?(:user_events, :make_attempts_count)
    add_column :user_events, :make_last_error, :text unless column_exists?(:user_events, :make_last_error)
    add_column :user_events, :updated_at, :datetime unless column_exists?(:user_events, :updated_at)

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

    change_column_null :user_events, :occurred_at, false if column_exists?(:user_events, :occurred_at)
    change_column_null :user_events, :updated_at, false if column_exists?(:user_events, :updated_at)

    add_index :user_events, :idempotency_key unless index_exists?(:user_events, :idempotency_key)
    unless index_exists?(:user_events, [:user_id, :event_name, :idempotency_key], name: "index_user_events_on_user_event_idempotency")
      add_index :user_events, [:user_id, :event_name, :idempotency_key],
        unique: true,
        where: "idempotency_key IS NOT NULL",
        name: "index_user_events_on_user_event_idempotency"
    end
    unless index_exists?(:user_events, [:make_delivery_status, :created_at], name: "index_user_events_on_make_status_and_created_at")
      add_index :user_events, [:make_delivery_status, :created_at],
        name: "index_user_events_on_make_status_and_created_at"
    end
  end
end
