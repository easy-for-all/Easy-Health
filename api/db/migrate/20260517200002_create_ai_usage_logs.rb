class CreateAiUsageLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_usage_logs do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :task_type,     null: false
      t.string  :model,         null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.string  :status,        null: false, default: "success"
      t.string  :error_summary
      t.timestamps
    end

    add_index :ai_usage_logs, [:user_id, :task_type, :created_at]
  end
end
