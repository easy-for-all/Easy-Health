class AddPositionToWorkoutDays < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_days, :position, :integer
  end
end
