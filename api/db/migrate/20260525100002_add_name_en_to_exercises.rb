class AddNameEnToExercises < ActiveRecord::Migration[7.1]
  def change
    add_column :exercises, :name_en, :string
  end
end
