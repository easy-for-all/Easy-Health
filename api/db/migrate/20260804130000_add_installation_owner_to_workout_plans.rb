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
    #
    # if_exists: NÃO é idempotência decorativa. Este índice nunca foi criado por
    # migration nenhuma deste repositório (só existia em bases que o ganharam à
    # mão), então "o índice existe" era uma suposição, não um fato do schema —
    # e foi ela que derrubou a API de produção com PG::UndefinedObject.
    remove_index :workout_plans, name: "index_workout_plans_one_active_per_user", if_exists: true

    # Consequência direta do índice nunca ter existido em produção: a invariante
    # "um plano ativo por dono" só era mantida pelo código, e o código tinha uma
    # corrida (ver WorkoutPlans::ActivatePlan). Bases antigas chegam aqui com
    # duplicados reais e o CREATE UNIQUE INDEX abaixo cai em PG::UniqueViolation.
    deactivate_duplicate_active_plans

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

  private

  # Reconcilia o passado para que o índice possa passar a valer no futuro.
  #
  # NADA é apagado: o plano anterior continua na tabela, com todo o histórico
  # pendurado nele, apenas deixa de ser o ativo. Em SQL puro e não via WorkoutPlan
  # de propósito — uma migration que depende de um model da aplicação quebra no
  # dia em que aquele model ganhar uma validação, um callback ou um default_scope
  # que não existiam quando ela foi escrita.
  #
  # "Mais recente" é created_at DESC, id DESC: o desempate por id importa porque
  # os duplicados reais nasceram com segundos (às vezes o mesmo segundo) de
  # diferença, então created_at sozinho não é determinístico.
  def deactivate_duplicate_active_plans
    %w[user_id app_installation_id].each do |owner_column|
      execute <<~SQL.squish
        UPDATE workout_plans
           SET active = false, updated_at = NOW()
         WHERE active = true
           AND #{owner_column} IS NOT NULL
           AND id NOT IN (
                 SELECT DISTINCT ON (#{owner_column}) id
                   FROM workout_plans
                  WHERE active = true
                    AND #{owner_column} IS NOT NULL
                  ORDER BY #{owner_column}, created_at DESC, id DESC
               )
      SQL
    end
  end
end
