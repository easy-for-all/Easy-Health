class CreateNotificationDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :notification_deliveries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :push_device, null: true, foreign_key: { to_table: :device_tokens }

      t.string :notification_type, null: false
      t.string :status, null: false, default: "scheduled"

      t.datetime :scheduled_for
      t.datetime :sent_at
      t.datetime :delivered_at
      t.datetime :opened_at
      t.datetime :clicked_at
      t.datetime :converted_at
      t.datetime :canceled_at
      t.string :cancel_reason

      t.string :provider_message_id
      t.string :idempotency_key
      t.jsonb :payload_json, null: false, default: {}
      t.string :error_code
      t.integer :retry_count, null: false, default: 0

      t.timestamps
    end

    add_index :notification_deliveries, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL"
    add_index :notification_deliveries, [:user_id, :notification_type]
    add_index :notification_deliveries, :status
    add_index :notification_deliveries, :scheduled_for
  end
end
