class CreatePublicProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :public_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :display_name
      t.boolean :avatar_visible, default: false, null: false
      t.boolean :city_visible, default: false, null: false
      t.boolean :country_visible, default: false, null: false
      t.text :public_bio
      t.boolean :show_workout_count, default: true, null: false
      t.boolean :show_streak, default: true, null: false
      t.boolean :show_points, default: false, null: false
      t.boolean :show_badges, default: false, null: false

      t.timestamps
    end
  end
end
