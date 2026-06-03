class FixPersonalClientUniqueIndex < ActiveRecord::Migration[8.1]
  def change
    remove_index :personal_client_relationships, column: [:personal_id, :client_id]
    # Unique active relationship: personal + client (only when client is present and active)
    add_index :personal_client_relationships,
              [:personal_id, :client_id],
              unique: true,
              where: "client_id IS NOT NULL AND status != 'removed'",
              name: "index_pcr_on_personal_and_client_active"
  end
end
