class AddDifficultyLevelToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :difficulty_level, :string
    add_index  :exercises, :difficulty_level
  end
end
