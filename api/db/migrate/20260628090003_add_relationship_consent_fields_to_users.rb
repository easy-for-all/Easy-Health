class AddRelationshipConsentFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :marketing_consent, :boolean, default: false, null: false
    add_column :users, :unsubscribed_at, :datetime
    add_column :users, :email_bounced_at, :datetime
    add_column :users, :last_marketing_email_sent_at, :datetime

    add_index :users, :marketing_consent
    add_index :users, :unsubscribed_at
    add_index :users, :email_bounced_at
  end
end
