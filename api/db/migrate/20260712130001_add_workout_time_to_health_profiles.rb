class AddWorkoutTimeToHealthProfiles < ActiveRecord::Migration[8.1]
  def change
    # Source of truth for "when the user usually trains". Captured in onboarding
    # and editable in the profile. Used to schedule the first-workout reminder.
    add_column :health_profiles, :preferred_workout_period, :string
    add_column :health_profiles, :preferred_workout_time, :time
    add_column :health_profiles, :workout_time_source, :string
    add_column :health_profiles, :preferred_workout_time_updated_at, :datetime
  end
end
