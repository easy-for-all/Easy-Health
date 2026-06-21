class CreateCoachInsights < ActiveRecord::Migration[8.1]
  def change
    create_table :coach_insights do |t|
      t.references :user,            null: false, foreign_key: true
      t.references :fitness_profile, null: false, foreign_key: true
      t.string  :insight_type, null: false
      t.string  :title,        null: false
      t.text    :message,      null: false
      t.string  :severity,     null: false, default: "info"
      t.string  :source,       null: false
      t.jsonb   :metadata,     null: false, default: {}
      t.datetime :read_at
      t.timestamps
    end

    add_index :coach_insights, [:user_id, :created_at]
    add_index :coach_insights, [:user_id, :read_at]
    add_index :coach_insights, :insight_type
  end
end
