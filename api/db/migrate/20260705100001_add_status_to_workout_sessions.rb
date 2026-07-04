class AddStatusToWorkoutSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_sessions, :status, :string, default: "completed", null: false
    add_index :workout_sessions, :status
  end
end
