class CreatePersonalNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :personal_notes do |t|
      t.bigint :personal_id, null: false
      t.bigint :client_id,   null: false
      t.text   :body,        null: false
      t.string :visibility,  default: "private", null: false

      t.timestamps
    end

    add_index :personal_notes, [:personal_id, :client_id]
    add_index :personal_notes, :personal_id
    add_foreign_key :personal_notes, :users, column: :personal_id
    add_foreign_key :personal_notes, :users, column: :client_id
  end
end
