module AnonymousSessions
  # Transfere para a conta recém-criada o que a instalação produziu antes dela:
  # respostas do wizard, planos e sessões executadas.
  #
  # Espelha o contrato de AppInstallations::LinkToUser de propósito — mesmo
  # Result, mesmo vocabulário fechado de códigos, nunca levanta para o chamador,
  # nunca rouba. As duas coisas respondem à mesma pergunta (de quem é este
  # aparelho) e precisam responder igual.
  class ClaimToUser
    STATUSES = %i[claimed already_claimed conflict nothing_to_claim invalid_input unexpected_error].freeze

    PERMANENT_STATUSES = %i[conflict invalid_input].freeze

    Result = Struct.new(:success, :status, :failure_code, :plans_claimed, :sessions_claimed, :profile_claimed,
                        keyword_init: true) do
      def claimed? = status == :claimed
      def permanent? = !success && PERMANENT_STATUSES.include?(status)
    end

    def initialize(user:, session:)
      @user = user
      @session = session
      @installation = session&.app_installation
    end

    def call
      return failure(:invalid_input, "claim_error") if @user.nil? || @session.nil? || @installation.nil?

      # Idempotente: o cliente reenvia em retomada de rascunho e em reload, e um
      # segundo claim do MESMO dono não pode virar erro nem duplicar nada.
      return success(:already_claimed) if @session.claimed_by_user_id == @user.id
      return conflict("user_conflict") if @session.claimed?

      # A posse do aparelho é decidida em UM lugar só. Se LinkToUser recusa
      # porque a instalação é de outra conta, o claim para aqui: instalação e
      # dados dela não podem acabar com donos diferentes.
      link = AppInstallations::LinkToUser.new(
        installation: @installation, user: @user, source: "anonymous_claim"
      ).call
      return conflict("user_conflict") if link.status == :conflict

      claim!
    rescue StandardError => e
      Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
      Rails.logger.error("[anonymous] claim failed: #{e.class}: #{e.message}")
      record_failure("claim_error")
      failure(:unexpected_error, "claim_error")
    end

    private

    def claim!
      plans = 0
      sessions = 0
      profile_claimed = false

      ActiveRecord::Base.transaction do
        profile_claimed = apply_profile_answers

        # Desativa os planos do usuário ANTES de mover, senão o índice parcial
        # "um plano ativo por usuário" estoura no meio da transação.
        @user.workout_plans.update_all(active: false)

        plans = WorkoutPlan.where(app_installation_id: @installation.id)
                           .update_all(user_id: @user.id, app_installation_id: nil, updated_at: Time.current)

        sessions = WorkoutSession.where(app_installation_id: @installation.id)
                                 .update_all(user_id: @user.id, app_installation_id: nil, updated_at: Time.current)

        # ai_usage_logs e ai_training_decision_logs NÃO são movidos. RateLimiter
        # conta AiUsageLog do dia por usuário com teto 3; trazer as gerações
        # anônimas junto faria a pessoa chegar à conta nova já bloqueada. O
        # ai_rationale continua acessível porque a associação é por plano.

        @session.update!(
          claimed_at: Time.current,
          claimed_by_user: @user,
          claim_attempts_count: @session.claim_attempts_count + 1,
          last_claim_failure_code: nil
        )
      end

      Result.new(success: true, status: :claimed, plans_claimed: plans, sessions_claimed: sessions,
                 profile_claimed: profile_claimed)
    end

    # As respostas do wizard viram uma HealthProfile de verdade. Merge e não
    # sobrescrita: a pessoa pode já ter um perfil (veio da Web antes), e apagar
    # o que ela respondeu lá seria perder dado para ganhar simplicidade.
    #
    # `save` e não `save!` DE PROPÓSITO. HealthProfile exige idade, peso, altura
    # e nível — e o wizard rápido nem sempre pergunta todos. Derrubar a
    # transação por um perfil incompleto faria a pessoa perder o PLANO que já
    # tinha gerado, para proteger uma conveniência: o plano é o valor, o perfil
    # é preenchível depois pela tela que já existe. O resultado devolve se deu
    # certo, para que a frequência disso seja mensurável em vez de invisível.
    def apply_profile_answers
      answers = @session.profile_answers.presence
      return false if answers.blank?

      attributes = answers.slice(*Workouts::InstallationOwner.profile_attribute_names)
                          .reject { |_key, value| value.nil? }
      return false if attributes.blank?

      profile = @user.health_profile || @user.build_health_profile
      profile.assign_attributes(attributes)
      return true if profile.save

      Rails.logger.info(
        "[anonymous] claim kept the plan but not the profile: #{profile.errors.full_messages.join(', ')}"
      )
      false
    end

    def conflict(code)
      record_failure(code)
      failure(:conflict, code)
    end

    def record_failure(code)
      @session&.update_columns(
        claim_attempts_count: @session.claim_attempts_count + 1,
        last_claim_failure_code: code,
        updated_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.warn("[anonymous] could not record claim failure: #{e.message}")
    end

    def success(status)
      Result.new(success: true, status: status, plans_claimed: 0, sessions_claimed: 0)
    end

    def failure(status, code)
      Result.new(success: false, status: status, failure_code: code, plans_claimed: 0, sessions_claimed: 0)
    end
  end
end
