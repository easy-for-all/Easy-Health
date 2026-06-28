class CreateRelationshipMessages < ActiveRecord::Migration[7.1]
  def change
    create_table :relationship_messages do |t|
      t.bigint   :user_id,               null: false
      t.bigint   :user_event_id

      t.string   :event_name,            null: false
      t.string   :journey_key
      t.string   :step_key
      t.string   :channel,               null: false
      t.string   :provider,              null: false
      t.string   :template_key
      t.string   :subject
      t.string   :recipient_email
      t.string   :status,                null: false, default: "pending"
      t.string   :provider_message_id
      t.jsonb    :provider_response_json, default: {}
      t.text     :error_message

      t.datetime :sent_at
      t.datetime :failed_at
      t.datetime :skipped_at

      t.jsonb    :metadata_json,         default: {}
      t.string   :idempotency_key

      t.timestamps
    end

    add_index :relationship_messages, :user_id
    add_index :relationship_messages, :user_event_id
    add_index :relationship_messages, :event_name
    add_index :relationship_messages, :journey_key
    add_index :relationship_messages, :template_key
    add_index :relationship_messages, :status
    add_index :relationship_messages, :provider_message_id
    add_index :relationship_messages, :idempotency_key, unique: true
  end
end
