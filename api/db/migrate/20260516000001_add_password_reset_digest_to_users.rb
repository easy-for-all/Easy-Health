class AddPasswordResetDigestToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :reset_password_token_digest, :string
    # reset_password_sent_at already exists from Devise — reused for our custom flow
  end
end
