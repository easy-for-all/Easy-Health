class AddAnalyticsColumnsToUsers < ActiveRecord::Migration[8.1]
  # test_account       — internal/QA/admin accounts excluded from every metric.
  # activation_platform — cohort_platform: the platform of the user's first
  #                       product analytics event (Android / Web / PWA). Written
  #                       once, never overwritten, so a user cannot be reclassified
  #                       by their most recent session.
  def change
    add_column :users, :test_account, :boolean, null: false, default: false
    add_column :users, :activation_platform, :string

    add_index :users, :test_account
    add_index :users, :activation_platform

    # Backfill admins as test accounts; anonymized accounts are already excluded
    # elsewhere but are flagged here too for consistency. Internal e-mail domains
    # are handled at runtime via ENV ANALYTICS_INTERNAL_EMAIL_DOMAINS.
    up_only do
      execute(<<~SQL.squish)
        UPDATE users
        SET test_account = true
        WHERE admin = true
           OR email LIKE '%@easyhealth.invalid'
      SQL
    end
  end
end
