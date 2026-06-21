module CoachEngine
  class PersonaClassifier
    def initialize(user:, fitness_profile:, health_profile: nil)
      @user = user
      @fitness_profile = fitness_profile
      @health_profile = health_profile || user.health_profile
    end

    def call
      persona = classified_persona
      {
        "primary_persona" => persona,
        "secondary_persona" => nil,
        "confidence" => confidence,
        "explanation" => explanation_for(persona),
        "evidence" => {
          "goal_present" => @health_profile&.goal.present?,
          "fitness_level_present" => @health_profile&.fitness_level.present?,
          "completed_sessions" => @user.workout_sessions.count
        }
      }
    end

    private

    def classified_persona
      return "general_health" unless @health_profile
      return "older_adult_mobility" if @health_profile.age.to_i >= 60
      return "high_frequency_athlete" if active_days_last_28 >= 20

      case @health_profile.goal
      when "gain_muscle"
        {
          "beginner" => "hypertrophy_beginner",
          "intermediate" => "hypertrophy_intermediate",
          "advanced" => "hypertrophy_advanced"
        }.fetch(@health_profile.fitness_level, "hypertrophy_beginner")
      when "lose_weight"
        adult_bmi_caution? ? "obese_weight_loss" : "weight_loss_beginner"
      when "body_definition"
        "recomposition"
      when "safe_return"
        "rehabilitation_return"
      else
        "general_health"
      end
    end

    def confidence
      value = 0.35
      value += 0.25 if @health_profile&.goal.present?
      value += 0.2 if @health_profile&.fitness_level.present?
      value += 0.1 if @health_profile&.age.present?
      value += 0.1 if @user.workout_sessions.exists?
      value.clamp(0, 0.95).round(2)
    end

    def explanation_for(persona)
      {
        "older_adult_mobility" => "A idade disponível pede uma abordagem conservadora, com mobilidade e força funcional.",
        "high_frequency_athlete" => "A frequência recente de treino é alta e sustenta uma persona de alta recorrência.",
        "hypertrophy_beginner" => "O objetivo de ganho muscular e o nível inicial indicam uma progressão de hipertrofia básica.",
        "hypertrophy_intermediate" => "O objetivo de ganho muscular e a experiência informada indicam hipertrofia intermediária.",
        "hypertrophy_advanced" => "O objetivo de ganho muscular e a experiência informada indicam hipertrofia avançada.",
        "obese_weight_loss" => "Os dados físicos e o objetivo pedem uma estratégia inicial conservadora e focada em aderência.",
        "weight_loss_beginner" => "O objetivo atual indica uma abordagem inicial de redução de peso com segurança.",
        "recomposition" => "O objetivo de definição corporal indica uma abordagem equilibrada de força e composição corporal.",
        "rehabilitation_return" => "O retorno seguro pede progressão gradual e atenção aos cuidados declarados.",
        "general_health" => "Os dados disponíveis indicam uma estratégia ampla de saúde e condicionamento."
      }.fetch(persona)
    end

    def active_days_last_28
      @user.workout_sessions.where(completed_at: 28.days.ago..).pluck(:completed_at).filter_map { |time| time&.to_date }.uniq.size
    end

    def adult_bmi_caution?
      return false unless @health_profile.age.to_i >= 18

      weight = @health_profile.weight_kg.to_f
      height_meters = @health_profile.height_cm.to_f / 100
      weight.positive? && height_meters.positive? && (weight / (height_meters**2)) >= 30
    end
  end
end
