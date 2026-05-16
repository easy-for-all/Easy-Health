class AddGifUrlAndInstructionsToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :gif_url, :string unless column_exists?(:exercises, :gif_url)
    add_column :exercises, :instructions, :text unless column_exists?(:exercises, :instructions)
  end
end
