class AddFieldsToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :difficulty, :string, default: "intermediate"
    add_column :exercises, :home_compatible, :boolean, default: false, null: false
  end
end
