class AddInstallationOwnerToWorkoutPlans < ActiveRecord::Migration[8.1]
  # Um plano passa a poder pertencer a um usuário OU a uma instalação. Só estas
  # duas tabelas — workout_plans e workout_sessions — precisam disso: o resto do
  # grafo (workout_days, workout_blocks, workout_day_exercises, exercise_sessions,
  # exercise_sets) já não tem dono próprio, pendura no plano ou na sessão.
  #
  # Deliberadamente NÃO se anulou user_id nas outras tabelas do caminho de
  # geração. O risco ali não são as queries where(user_id:), que continuariam
  # corretas, são os agregados globais (badges, streaks, Analytics::*) que
  # passariam a somar linhas anônimas sem que ninguém percebesse.
  def up
    change_column_null :workout_plans, :user_id, true
    add_reference :workout_plans, :app_installation, foreign_key: true, index: true

    # Exatamente um dono, sempre. Sem isto, "plano sem dono nenhum" e "plano com
    # dois donos" seriam estados representáveis, e o claim teria que adivinhar.
    add_check_constraint :workout_plans,
                         "(user_id IS NULL) <> (app_installation_id IS NULL)",
                         name: "workout_plans_single_owner"

    # O índice antigo deixa de restringir sozinho: com user_id anulável o
    # Postgres trata cada NULL como distinto, então TODAS as linhas anônimas
    # escapariam de "um plano ativo por dono" — em silêncio, que é a pior forma
    # de uma invariante morrer. Um índice parcial por espaço de identidade.
    remove_index :workout_plans, name: "index_workout_plans_one_active_per_user"

    add_index :workout_plans, :user_id,
              unique: true, where: "active = true AND user_id IS NOT NULL",
              name: "index_workout_plans_one_active_per_user"

    add_index :workout_plans, :app_installation_id,
              unique: true, where: "active = true AND app_installation_id IS NOT NULL",
              name: "index_workout_plans_one_active_per_installation"
  end

  def down
    remove_index :workout_plans, name: "index_workout_plans_one_active_per_installation"
    remove_index :workout_plans, name: "index_workout_plans_one_active_per_user"
    add_index :workout_plans, :user_id, unique: true, where: "active = true",
              name: "index_workout_plans_one_active_per_user"

    remove_check_constraint :workout_plans, name: "workout_plans_single_owner"
    remove_reference :workout_plans, :app_installation, foreign_key: true

    # Só volta a NOT NULL se não sobrou plano anônimo; reverter com dado anônimo
    # no banco significaria descartá-lo silenciosamente.
    change_column_null :workout_plans, :user_id, false
  end
end
