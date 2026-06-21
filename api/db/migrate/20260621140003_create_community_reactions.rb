class CreateCommunityReactions < ActiveRecord::Migration[8.0]
  def change
    create_table :community_reactions do |t|
      t.references :user,           null: false, foreign_key: true
      t.references :community_post, null: false, foreign_key: true
      t.string :reaction_type, default: "congrats", null: false

      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :community_reactions, [:user_id, :community_post_id], unique: true
  end
end
