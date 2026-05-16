class AddVideoUrlToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :video_url, :string
  end
end
