class CreatePersonalAlerts < ActiveRecord::Migration[8.0]
  def change
    create_table :personal_alerts do |t|
      t.references :personal, null: false, foreign_key: { to_table: :users }
      t.references :client, null: true, foreign_key: { to_table: :users }
      t.string :kind, null: false, default: "info"
      t.string :title, null: false
      t.text :body
      t.datetime :read_at
      t.timestamps
    end

    add_index :personal_alerts, [:personal_id, :read_at]
  end
end
