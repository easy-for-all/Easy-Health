class CreateWorkoutDays < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_days do |t|
      t.references :workout_plan, null: false, foreign_key: true
      t.integer :day_of_week
      t.string :name

      t.timestamps
    end
  end
end
