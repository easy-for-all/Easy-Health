class AddExerciseTypeToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :exercise_type, :string, default: "musculacao", null: false
    add_index :exercises, :exercise_type
  end
end
