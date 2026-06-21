class CreateCommunityComments < ActiveRecord::Migration[8.0]
  def change
    create_table :community_comments do |t|
      t.references :user,           null: false, foreign_key: true
      t.references :community_post, null: false, foreign_key: true
      t.text :body, null: false

      t.timestamps
    end

    add_index :community_comments, [:community_post_id, :created_at]
  end
end
