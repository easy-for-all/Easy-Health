class AddImageUrlToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :image_url, :string unless column_exists?(:exercises, :image_url)
  end
end
