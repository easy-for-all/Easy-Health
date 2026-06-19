class AddSourceToWorkoutSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_sessions, :source, :string
  end
end
