class CreateUserMedia < ActiveRecord::Migration[8.1]
  def change
    create_table :user_media do |t|
      t.references :user, null: false, foreign_key: true
      t.string :category, null: false
      t.text :notes
      t.datetime :captured_at, null: false

      t.timestamps
    end

    add_index :user_media, [:user_id, :category]
  end
end
