class AddCardioFieldsToWorkoutDayExercises < ActiveRecord::Migration[7.2]
  def change
    add_column :workout_day_exercises, :duration_minutes, :integer
    add_column :workout_day_exercises, :intensity, :string
  end
end
