class AddCompletionFieldsToWorkoutSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_sessions, :completion_status, :string, default: "completed", null: false
    add_column :workout_sessions, :completion_rate, :decimal, precision: 5, scale: 2
    add_column :workout_sessions, :skipped_exercises, :jsonb, default: []
    add_column :workout_sessions, :completed_sets_count, :integer
    add_column :workout_sessions, :planned_sets_count, :integer

    add_index :workout_sessions, :completion_status
  end
end
