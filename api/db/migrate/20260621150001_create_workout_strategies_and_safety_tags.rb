class CreateWorkoutStrategiesAndSafetyTags < ActiveRecord::Migration[8.0]
  def up
    add_column :exercises, :safety_tags, :text, array: true, default: [], null: false

    tag_exercises([ "Pular Corda", "Burpee", "Salto na Caixa", "Agachamento com Salto", "Polichinelo" ], "high_impact")
    tag_exercises([ "Agachamento", "Avanço", "Afundo Reverso", "Agachamento Isométrico", "Caminhada em Inclinação" ], "deep_knee_flexion")
    tag_exercises([ "Levantamento Terra", "Remada Curvada", "Swing com Kettlebell" ], "heavy_spinal_loading")
    tag_exercises([ "Abdominal", "Abdominal Bicicleta" ], "high_spinal_flexion")
    tag_exercises([ "Abdominal", "Abdominal Bicicleta", "Mountain Climber", "Escalador" ], "aggressive_core_loading")
    tag_exercises([ "Desenvolvimento", "Tríceps Francês", "Arremesso de Medicine Ball" ], "heavy_overhead_loading")
    tag_exercises([ "Mergulho no Banco", "Tríceps no Banco" ], "high_wrist_extension")
    tag_exercises([ "Corda Naval", "Remada no TRX" ], "unstable_shoulder_loading")
    tag_exercises([ "Corda Naval" ], "high_neck_loading")
    tag_exercises([ "Agachamento", "Avanço", "Afundo Reverso", "Agachamento Isométrico" ], "deep_hip_flexion")
    tag_exercises([ "Barra Fixa", "Remada no TRX", "Ponte Unilateral" ], "high_balance_demand")
    tag_exercises([ "Barra Fixa", "Burpee", "Salto na Caixa", "Swing com Kettlebell", "Borboleta" ], "advanced_skill")
    tag_exercises([ "Barra Fixa", "Salto na Caixa", "Remada no TRX" ], "high_fall_risk")

    create_table :workout_strategies do |t|
      t.references :user, null: false, foreign_key: true
      t.references :workout_plan, null: false, foreign_key: true, index: { unique: true }
      t.references :fitness_profile, foreign_key: true
      t.jsonb :strategy, null: false, default: {}
      t.string :strategy_version, null: false, default: "v1"
      t.timestamps
    end
  end

  def down
    drop_table :workout_strategies
    remove_column :exercises, :safety_tags
  end

  private

  def tag_exercises(names, tag)
    quoted_names = names.map { |name| connection.quote(name) }.join(", ")
    execute <<~SQL.squish
      UPDATE exercises
      SET safety_tags = array_append(safety_tags, #{connection.quote(tag)})
      WHERE name IN (#{quoted_names})
        AND NOT (#{connection.quote(tag)} = ANY(safety_tags))
    SQL
  end
end
