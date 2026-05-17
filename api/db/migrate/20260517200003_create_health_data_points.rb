class CreateHealthDataPoints < ActiveRecord::Migration[8.1]
  def change
    create_table :health_data_points do |t|
      t.references :user,       null: false, foreign_key: true
      t.references :user_media, null: true,  foreign_key: true
      t.string  :field_name,   null: false
      t.decimal :value,        precision: 10, scale: 3
      t.string  :unit
      t.string  :source_type,  null: false
      t.string  :status,       null: false, default: "pending_review"
      t.float   :confidence
      t.text    :raw_text
      t.text    :ai_notes
      t.datetime :collected_at
      t.timestamps
    end

    add_index :health_data_points, [:user_id, :field_name, :status]
  end
end
