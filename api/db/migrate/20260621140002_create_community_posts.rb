class CreateCommunityPosts < ActiveRecord::Migration[8.0]
  def change
    create_table :community_posts do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :post_type,  null: false
      t.string  :title
      t.text    :body
      t.jsonb   :metadata,   default: {}
      t.string  :visibility, default: "public", null: false

      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :community_posts, [:user_id, :created_at]
    add_index :community_posts, :visibility
  end
end
