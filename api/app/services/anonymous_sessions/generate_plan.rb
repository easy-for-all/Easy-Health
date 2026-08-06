module AnonymousSessions
  # Gera um plano para uma instalação sem conta.
  #
  # É o único lugar do sistema onde uma requisição sem autenticação alguma pode
  # provocar uma chamada paga a um provedor de IA. Tudo aqui existe por causa
  # disso: o contador com lock, o incremento na tentativa, e o disjuntor global.
  class GeneratePlan
    Result = Struct.new(:status, :plan, :error_code, :plans_remaining, keyword_init: true) do
      def success? = status == :generated
    end

    # Chave do contador global do dia. No cache e não numa tabela porque é um
    # disjuntor, não contabilidade — a contabilidade real está em ai_usage_logs.
    GLOBAL_COUNTER_TTL = 26.hours

    def initialize(session, params: {})
      @session = session
      @installation = session.app_installation
      @params = params
    end

    def call
      return failure(:unavailable, "anonymous_generation_disabled") unless AnonymousSessions.enabled?
      return failure(:unavailable, "anonymous_generation_capacity") if global_limit_reached?

      reservation = reserve_slot!
      return reservation if reservation.is_a?(Result)

      generate!
    rescue StandardError => e
      Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
      Rails.logger.error("[anonymous] plan generation failed: #{e.class}: #{e.message}")
      record_outcome("failed", e.class.name)
      failure(:error, "generation_failed")
    end

    private

    # Reserva a vaga ANTES de qualquer chamada ao provedor, e incrementa na
    # TENTATIVA e não no sucesso.
    #
    # Contar só sucessos parece mais justo e é a porta dos fundos: uma geração
    # que falha depois de chamar a OpenAI já custou dinheiro, e um cliente em
    # loop de retry geraria indefinidamente sem nunca "gastar" uma vaga.
    def reserve_slot!
      @session.with_lock do
        @session.roll_daily_counter!

        if @session.at_limit?
          @session.update!(last_generation_status: "limit_reached")
          return failure(:limit_reached, "anonymous_plan_limit_reached")
        end

        if @session.daily_limit_reached?
          @session.update!(last_generation_status: "limit_reached")
          return failure(:limit_reached, "anonymous_daily_limit_reached")
        end

        @session.plans_generated_count += 1
        @session.plans_generated_today_count += 1
        @session.last_generated_at = Time.current
        @session.first_generated_at ||= Time.current
        @session.save!
      end

      increment_global_counter
      nil
    end

    def generate!
      owner = Workouts::InstallationOwner.new(@installation)
      service = WorkoutPlanGeneratorService.new(owner, **generator_options)
      plan = service.call

      record_outcome("success", nil)
      Result.new(status: :generated, plan: plan, plans_remaining: @session.reload.plans_remaining)
    end

    # Mesmos parâmetros que o endpoint autenticado aceita. O perfil em si vem do
    # jsonb da sessão (via InstallationOwner#health_profile); o que chega aqui
    # são os overrides que o wizard manda junto com o pedido.
    def generator_options
      {
        days_per_week:        @params[:training_days_per_week]&.to_i,
        activity_preferences: Array(@params[:activity_preferences]).presence,
        modality:             @params[:modality].presence,
        split_type:           @params[:split_type].presence,
        cardio_type:          @params[:cardio_type].presence,
        cardio_format:        @params[:cardio_format].presence,
        custom_splits:        @params[:custom_splits].presence,
        training_location:    @params[:training_location].presence,
        selected_muscles:     @params[:selected_muscles].presence,
        muscle_priorities:    @params[:muscle_priorities].presence
      }
    end

    def record_outcome(status, error_code)
      @session.update_columns(
        last_generation_status: status,
        last_generation_error_code: error_code,
        updated_at: Time.current
      )
    rescue StandardError => e
      Rails.logger.warn("[anonymous] could not record generation outcome: #{e.message}")
    end

    def failure(status, error_code)
      Result.new(status: status, error_code: error_code, plans_remaining: @session.plans_remaining)
    end

    # ------------------------------------------------------------ disjuntor

    # Os limites por instalação são por instalação: dez mil instalações no teto
    # ainda somam trinta mil gerações, e nenhum contador local percebe isso.
    # Este é o único controle que limita a fatura.
    def global_limit_reached?
      global_counter >= AnonymousSessions.daily_global_max
    end

    def global_counter
      cached = Rails.cache.read(global_counter_key)
      return cached.to_i if cached

      # Reconcilia do banco quando o cache não tem o valor (restart, deploy,
      # expiração). Sem isto, reiniciar o Redis zeraria o disjuntor.
      count = AiTrainingDecisionLog.anonymous
                                   .where(generation_type: "workout_plan")
                                   .where(created_at: Analytics::ReportingTime.now.all_day)
                                   .count
      Rails.cache.write(global_counter_key, count, expires_in: GLOBAL_COUNTER_TTL)
      count
    end

    def increment_global_counter
      Rails.cache.write(global_counter_key, global_counter + 1, expires_in: GLOBAL_COUNTER_TTL)
    rescue StandardError => e
      # Um disjuntor que não consegue contar não pode derrubar a geração; o
      # limite por instalação continua valendo.
      Rails.logger.warn("[anonymous] global counter unavailable: #{e.message}")
    end

    def global_counter_key
      "anonymous_generation:#{Analytics::ReportingTime.today}"
    end
  end
end
