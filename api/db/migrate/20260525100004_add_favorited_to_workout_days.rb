class AddFavoritedToWorkoutDays < ActiveRecord::Migration[7.1]
  def change
    add_column :workout_days, :favorited, :boolean, default: false, null: false
  end
end
