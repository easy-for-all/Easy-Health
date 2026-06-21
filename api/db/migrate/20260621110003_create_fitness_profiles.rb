class CreateFitnessProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :fitness_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.string :primary_persona, null: false, default: "general_health"
      t.string :secondary_persona
      t.string :training_archetype, null: false, default: "balanced_full_body"
      t.string :secondary_training_archetype
      t.string :behavior_pattern, null: false, default: "unknown"
      t.string :fitness_level, null: false, default: "beginner"
      t.string :current_goal
      t.string :current_phase, null: false, default: "onboarding"
      t.string :classification_version, null: false, default: "v1"

      t.decimal :training_maturity, precision: 4, scale: 2, null: false, default: 0
      t.decimal :consistency_score, precision: 4, scale: 2, null: false, default: 0
      t.decimal :adherence_score, precision: 4, scale: 2, null: false, default: 0
      t.decimal :recovery_score, precision: 4, scale: 2, null: false, default: 0
      t.decimal :mobility_score, precision: 4, scale: 2, null: false, default: 0
      t.decimal :motivation_score, precision: 4, scale: 2, null: false, default: 0
      t.decimal :risk_score, precision: 4, scale: 2, null: false, default: 0
      t.decimal :preference_confidence_score, precision: 4, scale: 2, null: false, default: 0
      t.decimal :behavior_confidence_score, precision: 4, scale: 2, null: false, default: 0

      t.jsonb :preferred_body_focus, null: false, default: []
      t.jsonb :preferred_exercises, null: false, default: []
      t.jsonb :avoided_exercises, null: false, default: []
      t.jsonb :preferred_training_styles, null: false, default: []
      t.jsonb :available_equipment, null: false, default: []
      t.jsonb :physical_limitations, null: false, default: []
      t.datetime :last_recalculated_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
  end
end
