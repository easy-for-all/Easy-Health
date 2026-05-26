class CreateUserFavoriteExercises < ActiveRecord::Migration[7.1]
  def change
    create_table :user_favorite_exercises do |t|
      t.references :user, null: false, foreign_key: true
      t.references :exercise, null: false, foreign_key: true
      t.timestamps
    end

    add_index :user_favorite_exercises, [:user_id, :exercise_id], unique: true
  end
end
