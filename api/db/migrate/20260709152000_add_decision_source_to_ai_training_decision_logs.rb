class AddDecisionSourceToAiTrainingDecisionLogs < ActiveRecord::Migration[8.1]
  def change
    add_column :ai_training_decision_logs, :decision_source, :string, default: "ai", null: false
    add_index :ai_training_decision_logs, :decision_source
  end
end
