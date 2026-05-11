class AddGifUrlAndInstructionsToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :gif_url, :string
    add_column :exercises, :instructions, :text
  end
end
