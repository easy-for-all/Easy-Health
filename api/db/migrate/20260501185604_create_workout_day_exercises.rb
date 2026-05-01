class CreateWorkoutDayExercises < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_day_exercises do |t|
      t.references :workout_day, null: false, foreign_key: true
      t.references :exercise, null: false, foreign_key: true
      t.integer :sets
      t.integer :reps
      t.integer :rest_seconds
      t.integer :order_index

      t.timestamps
    end
  end
end
