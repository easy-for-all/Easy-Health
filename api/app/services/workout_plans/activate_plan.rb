module WorkoutPlans
  # O único lugar do sistema que troca qual é o plano ativo de um dono.
  #
  # Existe por causa de um incidente real: 52 usuários terminaram com dois
  # planos ativos, todos criados com segundos de diferença. O código já usava
  # transação, e transação não bastava:
  #
  #   BEGIN                              BEGIN
  #   UPDATE ... SET active = false      UPDATE ... SET active = false
  #   INSERT ... active = true           INSERT ... active = true
  #   COMMIT                             COMMIT
  #
  # Em READ COMMITTED cada UPDATE enxerga o snapshot do início do próprio
  # comando. O INSERT do outro lado ainda não existia quando o UPDATE começou,
  # então nenhum dos dois desativa o plano recém-criado pelo outro. Quando o
  # dono ainda não tem plano nenhum — a primeira geração, que é exatamente o
  # onboarding — nem sequer há linha para bloquear: os dois INSERTs passam sem
  # se tocarem. É write skew, e a única coisa que o resolve é serializar por
  # dono ANTES da leitura.
  #
  # O lock é a linha do dono no Postgres (SELECT ... FOR UPDATE), não um mutex
  # de processo: o deploy roda em container, e um mutex Ruby protegeria apenas
  # contra a concorrência que passa pelo mesmo processo — que é a única que já
  # não era problema.
  class ActivatePlan
    # A corrida perdida que nem o lock nem o índice conseguiram resolver: o
    # índice recusou o INSERT e, ao reler, não havia plano ativo para devolver.
    # Não é o caso normal de corrida (esse devolve o plano vencedor), é sinal de
    # que a invariante está inconsistente e alguém precisa olhar.
    class ActivationFailed < StandardError; end

    def self.call(owner:, attributes: {}, &block)
      new(owner: owner, attributes: attributes).call(&block)
    end

    def initialize(owner:, attributes: {})
      @owner = owner
      @attributes = attributes
    end

    # O bloco recebe o plano recém-criado e roda DENTRO da mesma transação e do
    # mesmo lock. É assim que o gerador monta dias e exercícios sem que exista,
    # em momento nenhum, um plano ativo pela metade visível para outra request.
    def call(&block)
      # with_lock abre a transação e trava a linha do dono. Duas requisições do
      # mesmo dono passam por aqui em fila; a segunda só lê depois que a
      # primeira comitou, e aí enxerga o plano que a primeira criou.
      @owner.with_lock do
        @owner.plans.active.update_all(active: false)
        plan = WorkoutPlan.create!(active: true, **@owner.plan_attributes, **@attributes)
        block&.call(plan)
        plan
      end
    rescue ActiveRecord::RecordNotUnique => e
      recover_from_race(e)
    end

    private

    # Última linha de defesa. Com o lock isto não deveria acontecer, e é
    # justamente por isso que não pode ser engolido em silêncio: se acontecer,
    # existe um caminho de escrita que não passa por aqui.
    #
    # O plano devolvido é o do vencedor, e ele está completo: o índice único só
    # recusa o INSERT depois que a transação concorrente comitou.
    def recover_from_race(error)
      existing = @owner.active_plan

      Observability::Events.workout_plan_activation_conflict(
        user_id: @owner.user&.id,
        app_installation_id: @owner.installation&.id,
        error_code: error.class.name,
        recovered: !existing.nil?
      )

      return existing if existing

      raise ActivationFailed, "active plan conflict without a recoverable active plan"
    end
  end
end
