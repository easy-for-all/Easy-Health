class AddImageUrlToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :image_url, :string
  end
end
