class CreatePersonalClientRelationships < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_client_relationships do |t|
      t.references :personal, null: false, foreign_key: { to_table: :users }
      t.references :client,   null: false, foreign_key: { to_table: :users }
      t.string  :status,              null: false, default: "invited"
      t.string  :invitation_code,     null: false
      t.datetime :invitation_expires_at
      t.datetime :invitation_sent_at
      t.datetime :started_at

      t.timestamps
    end

    add_index :personal_client_relationships, :invitation_code, unique: true
    add_index :personal_client_relationships, :status
    add_index :personal_client_relationships, [:personal_id, :client_id], unique: true
  end
end
