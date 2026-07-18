class CreatePushDispatches < ActiveRecord::Migration[8.1]
  def change
    create_table :push_dispatches do |t|
      # Identity of the Make-orchestrated request. `event_id` is the business
      # event the Make scenario acted on; `campaign_key` names the campaign.
      t.string :event_id
      t.references :user, null: false, foreign_key: true
      t.string :campaign_key
      t.string :notification_type, null: false

      # Rendered content (chosen by Make, validated by us). Never a device token.
      t.string :title
      t.string :body
      t.string :route
      t.jsonb :payload_json, null: false, default: {}

      t.string :status, null: false, default: "received"
      t.string :skip_reason
      t.string :idempotency_key, null: false
      t.string :correlation_id
      t.string :requested_by, null: false, default: "make"

      t.datetime :requested_at
      t.datetime :dispatched_at
      t.datetime :provider_accepted_at
      t.datetime :opened_at

      t.integer :tokens_attempted_count, null: false, default: 0
      t.integer :tokens_accepted_count, null: false, default: 0
      t.integer :tokens_rejected_count, null: false, default: 0

      t.string :last_error_code
      t.text :last_error_message

      t.timestamps
    end

    # Exclusive dedupe key: event_id + campaign_key + user_id + notification_type
    # (Phase 9). Guarantees the same Make dispatch is never sent twice.
    add_index :push_dispatches, :idempotency_key, unique: true
    add_index :push_dispatches, [ :user_id, :created_at ]
    add_index :push_dispatches, :status
  end
end
