class AddInstallationOwnerToAiLogs < ActiveRecord::Migration[8.1]
  # Custo e racional de IA de uma geração anônima. Sem isto, uma geração sem
  # conta não apareceria em lugar nenhum da contabilidade — que é justamente o
  # gasto novo que o modo anônimo introduz.
  #
  # Estas duas tabelas NÃO trocam de dono no claim, ao contrário do plano e da
  # sessão: RateLimiter conta AiUsageLog do dia por usuário (limite 3) e
  # AiWorkout::DailyLimitChecker conta AiTrainingDecisionLog. Reatribuir faria
  # quem gerou 3 planos anônimos hoje chegar à conta já bloqueado — punindo
  # exatamente a pessoa que o fluxo quer ativar.
  def up
    change_column_null :ai_usage_logs, :user_id, true
    add_reference :ai_usage_logs, :app_installation, foreign_key: true, index: true
    add_check_constraint :ai_usage_logs,
                         "user_id IS NOT NULL OR app_installation_id IS NOT NULL",
                         name: "ai_usage_logs_has_owner"

    change_column_null :ai_training_decision_logs, :user_id, true
    add_reference :ai_training_decision_logs, :app_installation, foreign_key: true, index: true
    add_check_constraint :ai_training_decision_logs,
                         "user_id IS NOT NULL OR app_installation_id IS NOT NULL",
                         name: "ai_training_decision_logs_has_owner"
  end

  def down
    remove_check_constraint :ai_training_decision_logs, name: "ai_training_decision_logs_has_owner"
    remove_reference :ai_training_decision_logs, :app_installation, foreign_key: true
    change_column_null :ai_training_decision_logs, :user_id, false

    remove_check_constraint :ai_usage_logs, name: "ai_usage_logs_has_owner"
    remove_reference :ai_usage_logs, :app_installation, foreign_key: true
    change_column_null :ai_usage_logs, :user_id, false
  end
end
