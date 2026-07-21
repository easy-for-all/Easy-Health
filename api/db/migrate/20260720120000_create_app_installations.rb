class CreateAppInstallations < ActiveRecord::Migration[8.1]
  # A stable record of one app INSTALLATION, keyed by a client-generated
  # installation_id (random UUID, persisted on the device). Distinct from:
  #   - device_tokens: one row per FCM token (rotates on reinstall/refresh)
  #   - users:         the authenticated account (an install may be anonymous)
  #   - product_analytics_events: the event stream
  #
  # This is what the Admin "APP ANDROID" panel counts, so ~150 real Android
  # installs stop being invisible (they were counted only via the write-once
  # users.activation_platform, which had no backfill — see docs/android-tracking-audit.md).
  #
  # user_id is nullable: an install exists before login and is associated to the
  # user AFTER authentication (never trusted from the client payload).
  def change
    create_table :app_installations do |t|
      t.string :installation_id, null: false

      # Identity — set only after the install authenticates.
      t.references :user, foreign_key: true, index: true
      # Link to the FCM token row when the same install registers for push.
      t.references :device_token, foreign_key: true, index: true

      # Platform / surface.
      t.string  :platform, null: false, default: "unknown"
      t.boolean :native, null: false, default: false

      # Device & app (non-PII).
      t.string :operating_system
      t.string :operating_system_version
      t.string :app_version
      t.string :app_build
      t.string :device_manufacturer
      t.string :device_model
      t.string :locale
      t.string :timezone

      # Push & consent.
      t.string  :notification_permission
      t.boolean :push_enabled, null: false, default: false
      t.boolean :analytics_consent, null: false, default: false

      # Provenance & tracking.
      t.string  :source
      t.integer :tracking_version

      # Timeline — installed_at only when known from a reliable source (never faked).
      t.datetime :installed_at
      t.datetime :first_seen_at
      t.datetime :tracking_started_at
      t.datetime :last_seen_at
      t.datetime :last_session_at
      t.datetime :last_authenticated_at

      t.timestamps
    end

    add_index :app_installations, :installation_id, unique: true
    add_index :app_installations, :platform
    add_index :app_installations, :last_seen_at
    add_index :app_installations, :app_version
  end
end
