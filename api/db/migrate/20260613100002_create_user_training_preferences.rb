class CreateUserTrainingPreferences < ActiveRecord::Migration[8.1]
  def change
    create_table :user_training_preferences do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :key,        null: false
      t.string  :value,      null: false
      t.string  :source
      t.decimal :confidence, precision: 3, scale: 2, default: 1.0
      t.datetime :last_seen_at

      t.timestamps
    end

    add_index :user_training_preferences, [:user_id, :key], unique: true
  end
end
