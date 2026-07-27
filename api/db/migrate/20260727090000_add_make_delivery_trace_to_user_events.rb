class AddMakeDeliveryTraceToUserEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :user_events, :make_first_attempt_at, :datetime unless column_exists?(:user_events, :make_first_attempt_at)
    add_column :user_events, :make_next_retry_at, :datetime unless column_exists?(:user_events, :make_next_retry_at)
    add_column :user_events, :make_delivered_to_provider_at, :datetime unless column_exists?(:user_events, :make_delivered_to_provider_at)
    add_column :user_events, :make_last_http_status, :integer unless column_exists?(:user_events, :make_last_http_status)
    add_column :user_events, :make_last_response_body, :text unless column_exists?(:user_events, :make_last_response_body)
    add_column :user_events, :make_last_error_class, :string unless column_exists?(:user_events, :make_last_error_class)
    add_column :user_events, :make_last_error_message, :text unless column_exists?(:user_events, :make_last_error_message)
    add_column :user_events, :make_delivery_duration_ms, :integer unless column_exists?(:user_events, :make_delivery_duration_ms)
    add_column :user_events, :make_processing_status, :string, default: "unknown", null: false unless column_exists?(:user_events, :make_processing_status)
    add_column :user_events, :make_processing_message, :text unless column_exists?(:user_events, :make_processing_message)
    add_column :user_events, :make_execution_id, :string unless column_exists?(:user_events, :make_execution_id)
    add_column :user_events, :make_callback_at, :datetime unless column_exists?(:user_events, :make_callback_at)
    add_column :user_events, :make_delivery_channels, :jsonb, default: [], null: false unless column_exists?(:user_events, :make_delivery_channels)
    add_column :user_events, :make_destination, :string unless column_exists?(:user_events, :make_destination)

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE user_events
             SET make_delivery_status = 'accepted_by_make',
                 make_delivered_to_provider_at = COALESCE(make_delivered_to_provider_at, make_last_attempt_at)
           WHERE make_delivery_status = 'delivered'
        SQL

        execute <<~SQL.squish
          UPDATE user_events
             SET make_delivery_status = CASE
                   WHEN make_attempts_count >= 5 THEN 'dead_letter'
                   ELSE 'retrying'
                 END,
                 make_last_error_message = COALESCE(make_last_error_message, make_last_error)
           WHERE make_delivery_status = 'failed'
        SQL

        execute <<~SQL.squish
          UPDATE user_events
             SET make_processing_status = 'unknown'
           WHERE make_processing_status IS NULL
        SQL
      end
    end

    add_index :user_events, :make_last_http_status unless index_exists?(:user_events, :make_last_http_status)
    add_index :user_events, :make_processing_status unless index_exists?(:user_events, :make_processing_status)
    add_index :user_events, :make_destination unless index_exists?(:user_events, :make_destination)
    add_index :user_events, :make_next_retry_at unless index_exists?(:user_events, :make_next_retry_at)
    add_index :user_events, :make_delivered_to_provider_at unless index_exists?(:user_events, :make_delivered_to_provider_at)
    add_index :user_events, :make_delivery_channels, using: :gin unless index_exists?(:user_events, :make_delivery_channels)
  end
end
