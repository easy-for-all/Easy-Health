module AiWorkout
  class PromptBuilder
    TEMPLATE_NAME = "workout_generation"

    def initialize(user:, fitness_profile:, workout_strategy: nil, days_per_week: 3,
                   fav_exercise_ids: [], available_exercises: {})
      @user               = user
      @fitness_profile    = fitness_profile
      @workout_strategy   = workout_strategy
      @days_per_week      = days_per_week
      @fav_exercise_ids   = fav_exercise_ids
      @available_exercises = available_exercises
    end

    def call
      template = AiPromptVersion.current_for(TEMPLATE_NAME)
      return fallback_build if template.nil?

      content = render_template(template.content)
      {
        prompt:            content,
        prompt_version_id: template.id
      }
    end

    private

    def render_template(content)
      vars = template_variables
      vars.each { |key, value| content = content.gsub("{{#{key}}}", value.to_s) }
      content
    end

    def template_variables
      {
        "persona"             => persona_context,
        "archetype"           => archetype_context,
        "behavior"            => behavior_context,
        "scores"              => scores_context,
        "strategy"            => strategy_context,
        "limitations"         => limitations_context,
        "equipment"           => equipment_context,
        "preferred_exercises" => preferred_exercises_context,
        "avoided_exercises"   => avoided_exercises_context,
        "recent_history"      => recent_history_context,
        "fitness_level"       => fitness_level,
        "goal"                => goal,
        "days_per_week"       => @days_per_week.to_s,
        "available_exercises" => available_exercises_context
      }
    end

    def persona_context
      return "Não classificado ainda" unless @fitness_profile
      parts = [@fitness_profile.primary_persona]
      parts << @fitness_profile.secondary_persona if @fitness_profile.secondary_persona.present?
      parts.map { |p| p.tr("_", " ") }.join(", ")
    end

    def archetype_context
      return "Não classificado ainda" unless @fitness_profile
      parts = [@fitness_profile.training_archetype]
      parts << @fitness_profile.secondary_training_archetype if @fitness_profile.secondary_training_archetype.present?
      parts.map { |p| p.tr("_", " ") }.join(", ")
    end

    def behavior_context
      return "Desconhecido" unless @fitness_profile&.behavior_pattern
      @fitness_profile.behavior_pattern.tr("_", " ")
    end

    def scores_context
      return "Não disponível" unless @fitness_profile
      [
        "Consistência: #{score_label(@fitness_profile.consistency_score)}",
        "Aderência: #{score_label(@fitness_profile.adherence_score)}",
        "Risco: #{score_label(@fitness_profile.risk_score)}",
        "Motivação: #{score_label(@fitness_profile.motivation_score)}"
      ].join(", ")
    end

    def score_label(value)
      return "N/A" if value.nil?
      v = value.to_f
      if v >= 7
        "alta (#{format('%.1f', v)})"
      elsif v >= 4
        "média (#{format('%.1f', v)})"
      else
        "baixa (#{format('%.1f', v)})"
      end
    end

    def strategy_context
      return "Sem estratégia definida" unless @workout_strategy
      strategy = @workout_strategy.is_a?(WorkoutStrategy) ? @workout_strategy.strategy : @workout_strategy
      return "Sem estratégia definida" if strategy.blank?

      parts = []
      parts << "Split: #{strategy['training_split']}" if strategy["training_split"]
      parts << "Frequência: #{strategy['weekly_frequency']}x/semana" if strategy["weekly_frequency"]
      parts << "Duração: #{strategy['session_duration_minutes']} min/sessão" if strategy["session_duration_minutes"]
      parts << "Intensidade: #{strategy['intensity_level']}" if strategy["intensity_level"]
      parts << "Volume: #{strategy['volume_level']}" if strategy["volume_level"]
      parts << "Progressão: #{strategy['progression_model']}" if strategy["progression_model"]
      parts << "Foco primário: #{Array(strategy['primary_focus']).join(', ')}" if strategy["primary_focus"].present?
      parts << "Foco corporal: #{Array(strategy['body_focus_priority']).join(', ')}" if strategy["body_focus_priority"].present?
      if strategy["notes_for_generator"].present?
        parts << "Observações: #{Array(strategy['notes_for_generator']).join('; ')}"
      end
      parts.join("\n")
    end

    def limitations_context
      profile = @user.health_profile
      limitations = Array(profile&.limitations).reject(&:blank?)
      limitations.any? ? limitations.join(", ") : "Nenhuma"
    end

    def equipment_context
      profile = @user.health_profile
      equipment = Array(profile&.available_equipment || @fitness_profile&.available_equipment).reject(&:blank?)
      equipment.any? ? equipment.join(", ") : "Não especificado"
    end

    def preferred_exercises_context
      return "Nenhum" if @fav_exercise_ids.empty?
      Exercise.where(id: @fav_exercise_ids).limit(10).map { |ex| "#{ex.name} (#{ex.muscle_group})" }.join(", ")
    end

    def avoided_exercises_context
      return "Nenhum" unless @fitness_profile
      avoided = Array(@fitness_profile.avoided_exercises).reject(&:blank?)
      avoided.any? ? avoided.join(", ") : "Nenhum"
    end

    def recent_history_context
      sessions = @user.workout_sessions.order(completed_at: :desc).limit(5)
      return "Nenhuma sessão registrada ainda." if sessions.empty?

      sessions.map do |s|
        date = s.completed_at&.strftime("%d/%m/%Y") || "?"
        duration = s.duration_minutes ? "#{s.duration_minutes} min" : "duração desconhecida"
        exercises_done = (s.exercise_logs || []).size
        [date, duration, "#{exercises_done} exercícios"].join(" | ")
      end.join("\n")
    end

    def available_exercises_context
      @available_exercises.map { |group, count| "#{group}: #{count} disponíveis" }.join(", ")
    end

    def fitness_level
      @user.health_profile&.fitness_level || "beginner"
    end

    def goal
      @user.health_profile&.goal || "saude"
    end

    def fallback_build
      { prompt: nil, prompt_version_id: nil }
    end
  end
end
