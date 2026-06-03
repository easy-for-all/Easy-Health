class MakeClientIdNullableInPersonalClientRelationships < ActiveRecord::Migration[8.1]
  def change
    change_column_null :personal_client_relationships, :client_id, true
  end
end
