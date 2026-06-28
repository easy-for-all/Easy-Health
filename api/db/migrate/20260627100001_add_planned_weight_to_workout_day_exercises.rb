class AddPlannedWeightToWorkoutDayExercises < ActiveRecord::Migration[7.1]
  def change
    add_column :workout_day_exercises, :planned_weight, :decimal, precision: 6, scale: 2
  end
end
