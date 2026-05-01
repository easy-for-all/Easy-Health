class CreateHealthProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :health_profiles do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :age
      t.decimal :weight_kg
      t.decimal :height_cm
      t.string :fitness_level
      t.string :goal

      t.timestamps
    end
  end
end
