class AddTrackingFieldsToWorkoutSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_sessions, :fatigue_level, :integer
    add_column :workout_sessions, :exercise_logs, :jsonb, default: [], null: false
  end
end
