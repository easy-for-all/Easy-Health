class CreateTrainerProfiles < ActiveRecord::Migration[8.0]
  def change
    create_table :trainer_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :display_name
      t.text   :bio
      t.string :cref
      t.string :status, default: "active", null: false

      t.timestamps
    end
  end
end
