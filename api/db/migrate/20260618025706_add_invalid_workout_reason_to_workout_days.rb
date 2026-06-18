class AddInvalidWorkoutReasonToWorkoutDays < ActiveRecord::Migration[8.1]
  def change
    add_column :workout_days, :invalid_workout_reason, :string
  end
end
