class AddIntelligenceMetadataToExercises < ActiveRecord::Migration[8.1]
  def change
    change_table :exercises, bulk: true do |t|
      t.string :technical_complexity
      t.string :risk_level
      t.string :calisthenics_skill
      t.boolean :requires_barbell_skill, default: false, null: false
      t.boolean :requires_bodyweight_strength, default: false, null: false
      t.string :movement_pattern
      t.boolean :compound
      t.boolean :unilateral, default: false, null: false
      t.text :objective_tags, array: true, default: [], null: false
      t.text :style_tags, array: true, default: [], null: false
      t.bigint :regression_exercise_id
    end

    add_index :exercises, :technical_complexity
    add_index :exercises, :risk_level
    add_index :exercises, :calisthenics_skill
    add_index :exercises, :regression_exercise_id
    add_foreign_key :exercises, :exercises, column: :regression_exercise_id
  end
end
