class CreateAiWorkoutChatConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_workout_chat_conversations do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :status, default: "collecting", null: false
      t.jsonb :collected_profile, default: {}, null: false
      t.jsonb :messages, default: [], null: false
      t.jsonb :generated_preview
      t.jsonb :guardrail_flags, default: {}, null: false
      t.integer :follow_up_rounds, default: 0, null: false
      t.bigint :workout_plan_id
      t.datetime :completed_at

      t.timestamps
    end

    add_index :ai_workout_chat_conversations, [:user_id, :status]
    add_index :ai_workout_chat_conversations, :workout_plan_id
  end
end
