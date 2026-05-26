class AddCaloriesEstimatedToWorkoutSessions < ActiveRecord::Migration[7.1]
  def change
    add_column :workout_sessions, :calories_estimated, :integer
  end
end
