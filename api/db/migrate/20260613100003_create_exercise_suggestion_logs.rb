class CreateExerciseSuggestionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :exercise_suggestion_logs do |t|
      t.references :user,              null: false, foreign_key: true
      t.integer    :current_exercise_id
      t.integer    :suggested_exercise_id
      t.string     :event_type,        null: false
      t.text       :intent_text
      t.jsonb      :parsed_intent,     default: {}
      t.integer    :score
      t.boolean    :accepted

      t.datetime :created_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
    end

    add_index :exercise_suggestion_logs, [:user_id, :created_at]
    add_index :exercise_suggestion_logs, [:user_id, :suggested_exercise_id]
  end
end
