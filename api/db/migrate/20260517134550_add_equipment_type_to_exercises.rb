class AddEquipmentTypeToExercises < ActiveRecord::Migration[8.1]
  def change
    add_column :exercises, :equipment_type, :string, default: "gym", null: false
    add_index :exercises, :equipment_type
  end
end
