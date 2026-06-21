module CoachEngine
  class ContinuousCoach
    INACTIVITY_DAYS       = 7
    LOW_ADHERENCE_THRESHOLD = 4.0
    HIGH_CONSISTENCY_THRESHOLD = 7.0
    HIGH_RISK_THRESHOLD   = 7.0
    DEDUP_HOURS           = 48

    def initialize(user:)
      @user = user
    end

    def call
      @fitness_profile = @user.fitness_profile
      return [] unless @fitness_profile

      insights = []
      insights.concat(check_inactivity)
      insights.concat(check_low_adherence)
      insights.concat(check_avoided_exercises)
      insights.concat(check_positive_progression)
      insights.concat(check_body_composition)
      insights.concat(check_high_consistency)
      insights.concat(check_high_risk)
      insights.concat(check_preference_confirmation)

      insights.compact
    end

    private

    def check_inactivity
      last_session = @user.workout_sessions.order(completed_at: :desc).first
      return [] if last_session&.completed_at&.> INACTIVITY_DAYS.days.ago

      days_inactive = last_session ? ((Time.current - last_session.completed_at) / 1.day).round : nil
      days_label    = days_inactive ? "#{days_inactive} dias" : "algum tempo"

      create_insight(
        type:    "inactivity",
        title:   "Hora de retomar!",
        message: "Você ficou #{days_label} sem treinar. Que tal recomeçar com uma sessão mais leve hoje?",
        severity: "warning",
        source:  "continuous_coach"
      )
    end

    def check_low_adherence
      return [] unless @fitness_profile.adherence_score.to_f < LOW_ADHERENCE_THRESHOLD
      return [] unless @fitness_profile.behavior_pattern == "abandons_long_workouts"

      create_insight(
        type:    "workout_adjustment",
        title:   "Treinos mais curtos podem ajudar",
        message: "Seus treinos longos estão difíceis de concluir. Vou sugerir sessões mais curtas na próxima geração de plano.",
        severity: "info",
        source:  "continuous_coach"
      )
    end

    def check_avoided_exercises
      coach_data = @fitness_profile.metadata&.dig("coach_engine", "behavior_analyst") || {}
      avoided    = Array(coach_data["avoided_patterns"]).reject(&:blank?)
      return [] if avoided.empty?

      first_avoided = avoided.first.to_s.humanize.downcase
      create_insight(
        type:    "preference_learning",
        title:   "Aprendi suas preferências",
        message: "Percebi que você costuma evitar #{first_avoided}. Vou ajustar seus próximos treinos para incluir alternativas mais confortáveis.",
        severity: "info",
        source:  "behavior_analyst"
      )
    end

    def check_positive_progression
      return [] unless @fitness_profile.consistency_score.to_f >= HIGH_CONSISTENCY_THRESHOLD

      recent_count = @user.workout_sessions
        .where(completed_at: 7.days.ago..)
        .count
      return [] unless recent_count >= 3

      create_insight(
        type:    "progression",
        title:   "Ótima semana!",
        message: "Você completou #{recent_count} treinos essa semana. Continue assim — podemos aumentar gradualmente a progressão!",
        severity: "success",
        source:  "progress_analyst"
      )
    end

    def check_body_composition
      recent_measurements = @user.health_data_points
        .where(field_name: %w[muscle_mass body_fat_pct weight_kg])
        .where(collected_at: 30.days.ago..)
        .order(:collected_at)
        .group_by(&:field_name)

      muscle_data = recent_measurements["muscle_mass"] || []
      fat_data    = recent_measurements["body_fat_pct"] || []
      return [] if muscle_data.size < 2 || fat_data.size < 2

      muscle_fell = muscle_data.last.value.to_f < muscle_data.first.value.to_f
      fat_fell    = fat_data.last.value.to_f < fat_data.first.value.to_f

      return [] unless muscle_fell && fat_fell

      create_insight(
        type:    "body_composition",
        title:   "Ajuste de estratégia",
        message: "Seu peso caiu, mas sua massa muscular também reduziu. Vamos reforçar o treino de força para preservar músculo.",
        severity: "warning",
        source:  "progress_analyst"
      )
    end

    def check_high_consistency
      return [] unless @fitness_profile.consistency_score.to_f >= HIGH_CONSISTENCY_THRESHOLD

      recent_count = @user.workout_sessions.where(completed_at: 7.days.ago..).count
      return [] unless recent_count >= 3
      return [] if already_created?("achievement")

      create_insight(
        type:    "achievement",
        title:   "Consistência em alta!",
        message: "Você está treinando de forma consistente. Isso é o que diferencia quem transforma resultados de longo prazo!",
        severity: "success",
        source:  "continuous_coach"
      )
    end

    def check_high_risk
      return [] unless @fitness_profile.risk_score.to_f >= HIGH_RISK_THRESHOLD

      create_insight(
        type:    "risk",
        title:   "Atenção ao treino",
        message: "Detectamos alguns fatores de risco no seu perfil. Prefira variações mais seguras e consulte um profissional de saúde se sentir dor.",
        severity: "warning",
        source:  "risk_analyst"
      )
    end

    def check_preference_confirmation
      archetype = @fitness_profile.training_archetype.to_s
      return [] unless archetype.present?

      archetype_labels = {
        "glute_focused"     => "glúteos e posteriores",
        "lower_body_focused" => "membros inferiores",
        "upper_body_focused" => "membros superiores",
        "aesthetic_hypertrophy" => "estética e definição",
        "strength_focused"  => "força",
        "weight_loss"       => "emagrecimento",
        "cardio_focused"    => "condicionamento cardio",
        "health_and_longevity" => "saúde e longevidade"
      }

      label = archetype_labels[archetype]
      return [] unless label
      return [] if already_created?("preference_learning")

      create_insight(
        type:    "preference_learning",
        title:   "Seu foco está definido",
        message: "Vou priorizar #{label} nos seus treinos, mantendo equilíbrio com o restante do corpo.",
        severity: "info",
        source:  "continuous_coach"
      )
    end

    def create_insight(type:, title:, message:, severity:, source:)
      return [] if already_created?(type)

      insight = CoachInsight.create!(
        user:            @user,
        fitness_profile: @fitness_profile,
        insight_type:    type,
        title:           title,
        message:         message,
        severity:        severity,
        source:          source
      )

      UserEventService.track(
        user:     @user,
        event:    :coach_insight_created,
        metadata: { insight_id: insight.id, insight_type: type }
      )

      [insight]
    rescue => e
      Rails.logger.warn("[ContinuousCoach] Could not create insight #{type}: #{e.message}")
      []
    end

    def already_created?(type)
      CoachInsight.where(
        user_id:      @user.id,
        insight_type: type,
        created_at:   DEDUP_HOURS.hours.ago..
      ).exists?
    end
  end
end
