class CreateWorkoutPlans < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_plans do |t|
      t.references :user, null: false, foreign_key: true
      t.boolean :active

      t.timestamps
    end
  end
end
