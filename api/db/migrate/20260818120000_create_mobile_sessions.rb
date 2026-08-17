class CreateMobileSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :mobile_sessions do |t|
      t.references :user, null: false, foreign_key: true, index: false

      # SHA-256 of the token. The raw token is returned to the client exactly
      # once, at issue time, and is never stored — same discipline as
      # mobile_auth_codes, so a database leak cannot be replayed as a session.
      t.string   :token_digest, null: false
      t.string   :platform,     null: false

      # Free-form correlation with app_installations.installation_id. Not a
      # foreign key: an installation may be registered after the session is
      # issued, and a missing installation must never block a login.
      t.string   :installation_id
      t.string   :app_version

      t.datetime :expires_at,  null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.string   :revocation_reason

      t.timestamps
    end

    add_index :mobile_sessions, :token_digest, unique: true
    add_index :mobile_sessions, :user_id
    # Drives the "revoke everything still valid for this user" path on logout
    # and account deletion without scanning the table.
    add_index :mobile_sessions, [:user_id, :revoked_at]
    add_index :mobile_sessions, :expires_at
  end
end
