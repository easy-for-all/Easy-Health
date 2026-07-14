class AddMuscleSelectionToHealthProfiles < ActiveRecord::Migration[8.1]
  def change
    # Grupos musculares que o usuário escolheu focar no treino de força
    # (subset de Exercise::MUSCLE_GROUPS) e, no modo avançado, a prioridade
    # por grupo ("high" | "normal" | "avoid"). Alimentam o gerador de plano.
    add_column :health_profiles, :selected_muscle_groups, :text, array: true, default: []
    add_column :health_profiles, :muscle_priorities, :jsonb, default: {}

    # O filtro por grupo (Exercise.where(muscle_group:)) fica no caminho quente
    # da geração e passa a ser usado com mais frequência com esta feature.
    add_index :exercises, :muscle_group
  end
end
