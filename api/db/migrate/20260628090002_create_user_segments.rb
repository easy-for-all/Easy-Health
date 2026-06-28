class CreateUserSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :user_segments do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :segment_name, null: false
      t.boolean :active, default: true, null: false
      t.string :reason
      t.datetime :calculated_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.jsonb :metadata_json, default: {}, null: false

      t.timestamps
    end

    add_index :user_segments, [:user_id, :segment_name], unique: true
    add_index :user_segments, [:segment_name, :active]
    add_index :user_segments, :calculated_at
  end
end
