class AddAccountTypeAndPrivacyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :account_type, :string, default: "regular", null: false
    add_column :users, :profile_visibility, :string, default: "private", null: false
    add_column :users, :community_enabled, :boolean, default: false, null: false
    add_column :users, :referral_code, :string

    add_index :users, :account_type
    add_index :users, :referral_code, unique: true
  end
end
