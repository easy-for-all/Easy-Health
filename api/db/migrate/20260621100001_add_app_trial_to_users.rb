class AddAppTrialToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :trial_started_at, :datetime
    add_column :users, :trial_ends_at, :datetime
    add_index :users, :trial_ends_at

    now = Time.current
    execute <<~SQL
      UPDATE users
      SET trial_started_at = '#{now.utc.iso8601}',
          trial_ends_at    = '#{(now + 7.days).utc.iso8601}'
      WHERE trial_started_at IS NULL
        AND id NOT IN (
          SELECT user_id FROM subscriptions
          WHERE status IN ('active', 'trialing')
        )
    SQL
  end

  def down
    remove_index :users, :trial_ends_at
    remove_column :users, :trial_ends_at
    remove_column :users, :trial_started_at
  end
end
