class EnhanceAiTrainingDecisionLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_training_decision_logs, :prompt_version_id,    :bigint
    add_column :ai_training_decision_logs, :generation_type,      :string,  default: "workout_plan"
    add_column :ai_training_decision_logs, :tokens_input,         :integer
    add_column :ai_training_decision_logs, :tokens_output,        :integer
    add_column :ai_training_decision_logs, :estimated_cost_cents, :decimal, precision: 10, scale: 6
    add_column :ai_training_decision_logs, :status,               :string,  default: "success"
    add_column :ai_training_decision_logs, :error_message,        :text
    add_column :ai_training_decision_logs, :output_summary,       :jsonb,   default: {}

    add_index :ai_training_decision_logs, :prompt_version_id
    add_index :ai_training_decision_logs, [:user_id, :created_at]
    add_index :ai_training_decision_logs, :status

    add_foreign_key :ai_training_decision_logs, :ai_prompt_versions,
                    column: :prompt_version_id
  end
end
