class CreateMobileAuthCodes < ActiveRecord::Migration[8.1]
  def change
    create_table :mobile_auth_codes do |t|
      t.string :code_digest, null: false
      t.references :user, null: false, foreign_key: true
      t.string :platform, null: false
      t.datetime :expires_at, null: false
      t.datetime :used_at

      t.timestamps
    end

    add_index :mobile_auth_codes, :code_digest, unique: true
    add_index :mobile_auth_codes, [:platform, :expires_at]
    add_index :mobile_auth_codes, [:user_id, :used_at]
  end
end
