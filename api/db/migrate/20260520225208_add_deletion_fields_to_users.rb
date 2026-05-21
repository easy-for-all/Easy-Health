class AddDeletionFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deletion_requested_at, :datetime
    add_column :users, :anonymized_at, :datetime
  end
end
