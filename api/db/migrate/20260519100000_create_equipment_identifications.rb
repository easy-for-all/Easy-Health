class CreateEquipmentIdentifications < ActiveRecord::Migration[7.2]
  def change
    create_table :equipment_identifications do |t|
      t.references :user,     null: false, foreign_key: true
      t.references :exercise, null: true,  foreign_key: true
      t.string  :image_checksum
      t.string  :equipment_name
      t.string  :localized_name
      t.float   :confidence
      t.string  :muscle_groups, array: true, default: []
      t.boolean :compatible
      t.text    :reason
      t.jsonb   :raw_response
      t.timestamps
    end

    add_index :equipment_identifications, :image_checksum
  end
end
