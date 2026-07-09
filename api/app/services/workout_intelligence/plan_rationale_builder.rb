module WorkoutIntelligence
  # Builds the same shape of "why this plan" content the AI path already
  # produces (rationale/personalization_reason/user_explanation/coach_notes),
  # but from the rule-based/strategy decision instead of an LLM call — so a
  # plan that never touched AI still has real content for the frontend's
  # "Por que este plano?" section instead of nil.
  class PlanRationaleBuilder
    GOAL_LABELS = {
      "strength" => "ganho de força",
      "hypertrophy" => "hipertrofia",
      "conditioning" => "condicionamento",
      "mobility" => "mobilidade",
      "health" => "saúde geral"
    }.freeze

    LEVEL_LABELS = { "beginner" => "iniciante", "intermediate" => "intermediário", "advanced" => "avançado" }.freeze

    def initialize(health_profile:, fitness_level:, goal:, template:, weekly_volume_targets:, validation:, decision_source:)
      @health_profile = health_profile
      @fitness_level = fitness_level
      @bucket = GoalTrainingProfile.normalize_goal(goal)
      @template = Array(template)
      @weekly_volume_targets = weekly_volume_targets || {}
      @validation = validation
      @decision_source = decision_source
    end

    def call
      {
        training_method: training_method,
        plan_name: plan_name,
        rationale: rationale,
        personalization_reason: personalization_reason,
        user_explanation: user_explanation,
        coach_notes: coach_notes,
        progression_strategy: progression_strategy,
        safety_notes: safety_notes,
        week_structure: @template
      }
    end

    private

    def goal_label
      GOAL_LABELS.fetch(@bucket, "saúde geral")
    end

    def level_label
      LEVEL_LABELS.fetch(@fitness_level, "iniciante")
    end

    def training_method
      names = @template.map { |d| d[:name].to_s }
      return "ppl" if names.any? { |n| n =~ /push/i } && names.any? { |n| n =~ /pull/i }

      case @template.size
      when 1 then "full_body"
      when 2 then "upper_lower"
      when 3 then "abc"
      else "custom"
      end
    end

    def plan_name
      "Plano de #{goal_label.capitalize} — #{@template.size}x/semana"
    end

    def rationale
      "Montamos #{@template.size} treino#{@template.size == 1 ? '' : 's'} por semana com foco em #{goal_label}, " \
      "ajustado ao seu nível #{level_label}. #{volume_summary}"
    end

    def volume_summary
      return "" if @weekly_volume_targets.empty?

      top_groups = @weekly_volume_targets.sort_by { |_, v| -v }.first(3).map { |group, _| group.tr("_", " ") }
      "Priorizamos #{top_groups.join(', ')} no volume semanal."
    end

    def personalization_reason
      "Perfil #{level_label}, objetivo #{goal_label}."
    end

    def user_explanation
      duration = @health_profile&.session_duration_minutes
      style = Array(@health_profile&.preferred_training_styles).first
      parts = [ "Treino adaptado para #{goal_label}" ]
      parts << "sessões de #{duration} minutos" if duration
      parts << "com influência de #{style}" if style.present? && style != "unknown"
      parts.join(", ") + "."
    end

    def coach_notes
      fixes = Array(@validation&.auto_fixes).select { |f| f[:code] == :substituted_exercise }
      return nil if fixes.empty?

      descriptions = fixes.first(3).map { |f| "substituímos #{f[:from]} por #{f[:to]} (mais adequado ao seu nível)" }
      descriptions.join("; ") + "."
    end

    def progression_strategy
      case @fitness_level
      when "beginner" then "adaptation"
      when "advanced" then "undulating"
      else "linear"
      end
    end

    def safety_notes
      Array(@validation&.warnings).map { |w| w[:message] }.compact
    end
  end
end
