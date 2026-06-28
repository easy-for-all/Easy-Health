class CreateCoachRecommendations < ActiveRecord::Migration[7.1]
  def change
    create_table :coach_recommendations do |t|
      t.references :user,     null: false, foreign_key: true
      t.references :exercise, null: true,  foreign_key: true
      t.string  :recommendation_type, null: false
      t.string  :status,              null: false, default: "pending"
      t.string  :title
      t.text    :message
      t.string  :exercise_name
      t.decimal :current_value,     precision: 6, scale: 2
      t.decimal :recommended_value, precision: 6, scale: 2
      t.string  :unit
      t.decimal :confidence,        precision: 4, scale: 2
      t.jsonb   :reasons,           default: []
      t.jsonb   :metadata,          default: {}
      t.datetime :accepted_at
      t.datetime :dismissed_at
      t.timestamps
    end

    add_index :coach_recommendations, [:user_id, :status]
    add_index :coach_recommendations,
              [:user_id, :exercise_id, :recommendation_type, :status],
              name: "idx_coach_recs_unique_pending"
  end
end
