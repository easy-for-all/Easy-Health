class CreateSharedWorkouts < ActiveRecord::Migration[8.1]
  def change
    create_table :shared_workouts do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :token, null: false
      t.string :visibility, default: "private_link", null: false
      t.string :title
      t.jsonb :snapshot, default: {}, null: false
      t.boolean :include_weights, default: false, null: false
      t.boolean :include_notes, default: false, null: false
      t.datetime :expires_at
      t.integer :view_count, default: 0, null: false

      t.timestamps
    end

    add_index :shared_workouts, :token, unique: true
  end
end
