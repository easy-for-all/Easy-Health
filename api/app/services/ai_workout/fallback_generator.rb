module AiWorkout
  class FallbackGenerator
    def initialize(user:, days_per_week: nil, reason: "ai_failure")
      @user         = user
      @days_per_week = days_per_week
      @reason       = reason
    end

    def call
      result = generate_plan
      log_fallback_used(result)
      result
    end

    private

    def generate_plan
      profile = @user.health_profile
      level   = profile&.fitness_level || "beginner"
      days    = (@days_per_week || profile&.training_days_per_week || 3).clamp(1, 6)

      template = select_template(level, days)
      sets_reps = WorkoutPlanGeneratorService::SETS_REPS[level] ||
                  WorkoutPlanGeneratorService::SETS_REPS["beginner"]

      {
        valid:           true,
        fallback:        true,
        fallback_reason: @reason,
        data:            {
          training_method:        "full_body",
          plan_name:              "Plano #{level.capitalize}",
          rationale:              "Treino gerado por regras locais (fallback). Não foi possível usar a IA neste momento.",
          personalization_reason: "Plano baseado no seu nível (#{level}) e disponibilidade (#{days}x/semana).",
          user_explanation:       "Montamos um treino seguro para você com base no seu perfil. Em breve a personalização completa estará disponível.",
          coach_notes:            "Fallback ativo. Motivo: #{@reason}",
          week_structure:         template,
          sets_reps:              sets_reps,
          progression_strategy:   "Progressão linear básica: aumente 1 repetição por semana.",
          safety_notes:           ["Aqueça 5-10 minutos antes de cada treino", "Descanse 48h entre treinos do mesmo grupo muscular"]
        }
      }
    end

    def select_template(level, days)
      templates = WorkoutPlanGeneratorService::STRENGTH_TEMPLATES
      explicit  = WorkoutPlanGeneratorService::EXPLICIT_SPLITS

      if level == "beginner" && days <= 3
        [{ name: "Full Body", muscle_groups: %w[chest back legs core] }]
      elsif explicit.key?("upper_lower") && days == 4
        explicit["upper_lower"] * 2
      else
        templates[days] || templates[3]
      end
    end

    def log_fallback_used(result)
      return unless @user.active_workout_plan

      plan = @user.active_workout_plan
      existing = AiTrainingDecisionLog.find_by(workout_plan_id: plan.id)
      return if existing

      AiTrainingDecisionLog.create!(
        user_id:         @user.id,
        workout_plan_id: plan.id,
        model_used:      "fallback",
        training_method: result.dig(:data, :training_method),
        rationale:       result.dig(:data, :rationale),
        status:          "fallback_used",
        error_message:   @reason,
        generation_type: "workout_plan"
      )
    rescue => e
      Rails.logger.warn("[AiWorkout::FallbackGenerator] Could not log fallback: #{e.message}")
    end
  end
end
