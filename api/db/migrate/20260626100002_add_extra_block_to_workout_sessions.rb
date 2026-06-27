class AddExtraBlockToWorkoutSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_sessions, :extra_block_type, :string
    add_column :workout_sessions, :extra_block_data, :jsonb, default: {}
    add_column :workout_sessions, :extra_started_at, :datetime
    add_column :workout_sessions, :extra_completed_at, :datetime
  end
end
