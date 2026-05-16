class AddSetupGuideToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :setup_guide, :text
  end
end
