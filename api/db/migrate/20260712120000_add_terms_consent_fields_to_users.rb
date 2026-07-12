class AddTermsConsentFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :terms_accepted_at, :datetime
    add_column :users, :privacy_policy_accepted_at, :datetime
    add_column :users, :terms_version, :string
    add_column :users, :privacy_policy_version, :string
    add_column :users, :consent_source, :string
  end
end
