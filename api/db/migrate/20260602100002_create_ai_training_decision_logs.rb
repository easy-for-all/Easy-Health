class CreateAiTrainingDecisionLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_training_decision_logs do |t|
      t.references :user,         null: false, foreign_key: true
      t.references :workout_plan, null: false, foreign_key: true
      t.string  :training_method
      t.text    :rationale
      t.text    :progression_strategy
      t.jsonb   :safety_notes,   default: []
      t.jsonb   :week_structure, default: []
      t.jsonb   :input_summary,  default: {}
      t.string  :model_used
      t.timestamps
    end
  end
end
