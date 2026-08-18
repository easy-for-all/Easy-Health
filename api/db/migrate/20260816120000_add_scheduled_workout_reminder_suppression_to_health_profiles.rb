class AddScheduledWorkoutReminderSuppressionToHealthProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :health_profiles, :scheduled_workout_reminder_suppressed_at, :datetime
    add_column :health_profiles, :scheduled_workout_reminder_suppression_reason, :string
    add_column :health_profiles, :scheduled_workout_reminder_suppression_metadata, :jsonb, default: {}, null: false

    add_index :health_profiles,
              :scheduled_workout_reminder_suppressed_at,
              name: "idx_health_profiles_on_swr_suppressed_at",
              where: "scheduled_workout_reminder_suppressed_at IS NOT NULL"
  end
end
