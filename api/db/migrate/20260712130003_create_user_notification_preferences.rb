class CreateUserNotificationPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :user_notification_preferences do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      # Opt-in flags. All default OFF — no push without explicit consent.
      t.boolean :push_enabled, null: false, default: false
      t.boolean :workout_reminders_enabled, null: false, default: false
      t.boolean :workout_ready_enabled, null: false, default: false

      # Optional mirror of users.time_zone (source of truth stays on the user).
      t.string :timezone
      t.integer :max_pushes_per_week, null: false, default: 2

      # Activation flow bookkeeping (max 2 pushes: reminder + recovery).
      t.datetime :activation_reminder_sent_at
      t.datetime :activation_recovery_sent_at
      t.datetime :activation_notifications_completed_at

      # Permission / pre-permission lifecycle.
      t.datetime :prepermission_answered_at
      t.datetime :permission_requested_at
      t.datetime :permission_granted_at

      t.datetime :notifications_disabled_at
      t.string :disabled_reason

      # Deterministic, set-once experiment variant ("treatment" | "control").
      t.string :activation_push_variant

      t.timestamps
    end
  end
end
