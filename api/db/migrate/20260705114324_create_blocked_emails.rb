class CreateBlockedEmails < ActiveRecord::Migration[8.1]
  def change
    create_table :blocked_emails do |t|
      t.string :email, null: false
      t.bigint :user_id
      t.datetime :blocked_at, null: false

      t.timestamps
    end

    add_index :blocked_emails, :email, unique: true
  end
end
