class ExtendDeviceTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :device_tokens, :device_identifier, :string
    add_column :device_tokens, :app_version, :string
    add_column :device_tokens, :os_version, :string
    add_column :device_tokens, :enabled, :boolean, null: false, default: true
    add_column :device_tokens, :permission_status, :string
    add_column :device_tokens, :last_seen_at, :datetime
    add_column :device_tokens, :token_refreshed_at, :datetime
    add_column :device_tokens, :invalidated_at, :datetime
    add_column :device_tokens, :invalidation_reason, :string

    add_index :device_tokens, :enabled
    add_index :device_tokens, :invalidated_at
  end
end
