class CreateAnonymousOnboardingSessions < ActiveRecord::Migration[8.1]
  # O estado de quem usa o app sem conta, e a ÚNICA fonte autoritativa do limite
  # de treinos anônimos. Contar planos com um SELECT em workout_plans não serve:
  # uma geração que falha depois de chamar o provedor custou dinheiro e não
  # deixou plano, então o contador precisa ser independente do resultado.
  #
  # profile_answers guarda as respostas do wizard como jsonb em vez de criar uma
  # HealthProfile órfã. O gerador só LÊ o perfil; para anônimo ele recebe uma
  # HealthProfile não persistida montada daqui, e é este jsonb que o claim
  # replica numa HealthProfile de verdade.
  def change
    create_table :anonymous_onboarding_sessions do |t|
      t.references :app_installation, null: false, foreign_key: true, index: { unique: true }

      t.jsonb :profile_answers, null: false, default: {}

      t.integer :plans_generated_count, null: false, default: 0
      t.integer :plans_generated_today_count, null: false, default: 0
      t.date    :counter_date

      t.string   :last_generation_status
      t.string   :last_generation_error_code
      t.datetime :first_generated_at
      t.datetime :last_generated_at

      t.datetime   :claimed_at
      t.references :claimed_by_user, foreign_key: { to_table: :users }, index: true
      t.integer    :claim_attempts_count, null: false, default: 0
      t.string     :last_claim_failure_code

      t.timestamps
    end

    # Guardrail do painel: "quantas instalações bateram o teto" e "quantas
    # falharam ao gerar" são leituras diretas, sem varrer a tabela inteira.
    add_index :anonymous_onboarding_sessions, :plans_generated_count
    add_index :anonymous_onboarding_sessions, :last_generation_status
    add_index :anonymous_onboarding_sessions, :claimed_at
  end
end
