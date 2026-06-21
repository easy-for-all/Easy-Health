module CoachEngine
  class WorkoutStrategist
    VERSION = "v1".freeze
    SHORT_SESSION_MINUTES = 35
    BEHAVIOR_OVERRIDE_CONFIDENCE = 0.6
    CARDIO_ARCHETYPES = %w[cardio_focused mobility_focused functional_fitness].freeze
    LOWER_GROUPS = %w[legs glutes calves].freeze
    UPPER_GROUPS = %w[chest back shoulders biceps triceps].freeze

    BODY_FOCUS_GROUPS = {
      "glutes" => %w[glutes legs],
      "legs" => %w[legs glutes calves],
      "abs" => %w[core],
      "arms" => %w[biceps triceps],
      "chest" => %w[chest],
      "back" => %w[back],
      "shoulders" => %w[shoulders],
      "mobility_posture" => %w[core],
      "conditioning_cardio" => []
    }.freeze

    def initialize(user:, fitness_profile: nil, health_profile: nil)
      @user = user
      @fitness_profile = fitness_profile || user.fitness_profile
      @health_profile = health_profile || user.health_profile
    end

    def call
      frequency = adjusted_frequency
      duration = adjusted_duration
      focus = focus_plan
      {
        "strategy_version" => VERSION,
        "primary_persona" => primary_persona,
        "training_archetype" => training_archetype,
        "behavior_pattern" => behavior_pattern,
        "training_split" => training_split(frequency),
        "weekly_frequency" => frequency,
        "session_duration_minutes" => duration,
        "primary_focus" => focus.fetch(:primary),
        "secondary_focus" => focus.fetch(:secondary),
        "body_focus_priority" => focus.fetch(:priority),
        "cardio_strategy" => cardio_strategy,
        "strength_strategy" => strength_strategy,
        "mobility_strategy" => mobility_strategy,
        "progression_model" => progression_model,
        "intensity_level" => intensity_level,
        "volume_level" => volume_level,
        "forbidden_exercises" => forbidden_safety_tags,
        "preferred_exercises" => preferred_exercise_ids,
        "avoided_exercises" => avoided_exercise_ids,
        "recommended_exercise_patterns" => recommended_patterns,
        "notes_for_generator" => generator_notes,
        "user_facing_explanation" => user_facing_explanation
      }
    end

    private

    def coach_engine
      @coach_engine ||= @fitness_profile&.metadata&.dig("coach_engine") || {}
    end

    def agent_result(name)
      coach_engine.fetch(name, {})
    end

    def primary_persona
      @fitness_profile&.primary_persona.presence || "general_health"
    end

    def training_archetype
      @fitness_profile&.training_archetype.presence || "balanced_full_body"
    end

    def behavior_pattern
      @fitness_profile&.behavior_pattern.presence || "unknown"
    end

    def behavior_confident?
      agent_result("behavior").fetch("confidence", 0).to_f >= BEHAVIOR_OVERRIDE_CONFIDENCE
    end

    def behavior_patterns
      return [] unless behavior_confident?

      [ behavior_pattern, *Array(agent_result("behavior")["preferred_patterns"]), *Array(agent_result("behavior")["avoided_patterns"]) ].uniq
    end

    def risk_result
      agent_result("risk")
    end

    def risk_score
      @fitness_profile&.risk_score.to_f
    end

    def high_risk?
      risk_score >= 7 || %w[older_adult_mobility rehabilitation_return].include?(primary_persona) || sensitive_training_context?
    end

    def sensitive_training_context?
      @health_profile&.training_context.in?(%w[postpartum pregnant])
    end

    def declared_frequency
      (@health_profile&.training_days_per_week || 3).clamp(1, 6)
    end

    def adjusted_frequency
      return [ declared_frequency - 1, 1 ].max if behavior_patterns.intersect?(%w[low_adherence inconsistent_usage])

      declared_frequency
    end

    def adjusted_duration
      declared = @health_profile&.session_duration_minutes || default_duration
      behavior_patterns.include?("consistent_short_sessions") ? [ declared, SHORT_SESSION_MINUTES ].min : declared
    end

    def default_duration
      return SHORT_SESSION_MINUTES if high_risk? || @fitness_profile&.fitness_level == "beginner"

      45
    end

    def training_split(frequency)
      return "cardio_mobility" if CARDIO_ARCHETYPES.include?(training_archetype) || mobility_goal?
      return "full_body" if frequency <= 2 || high_risk? || @fitness_profile&.fitness_level == "beginner"
      return "abc" if frequency == 3 && %w[aesthetic_hypertrophy strength_focused].include?(training_archetype)
      return "upper_lower" if frequency == 4
      return "push_pull_legs" if frequency >= 5

      "full_body"
    end

    def mobility_goal?
      @health_profile&.goal == "mobility"
    end

    def focus_plan
      primary = archetype_focus
      declared = declared_body_focus
      primary = declared if primary.empty? && declared.any?
      primary = %w[chest back legs core] if primary.empty?
      secondary = balance_groups_for(primary)

      {
        primary: primary.uniq,
        secondary: secondary,
        priority: (primary + secondary).uniq
      }
    end

    def archetype_focus
      case training_archetype
      when "glute_focused" then %w[glutes legs]
      when "lower_body_focused" then LOWER_GROUPS
      when "upper_body_focused" then UPPER_GROUPS
      when "aesthetic_hypertrophy" then %w[chest back shoulders legs]
      when "strength_focused" then %w[legs chest back]
      when "athletic_performance" then %w[legs core]
      when "weight_loss", "body_recomposition" then %w[legs back chest]
      when "cardio_focused" then []
      when "mobility_focused", "health_and_longevity", "rehabilitation" then %w[core legs]
      else []
      end
    end

    def declared_body_focus
      Array(@fitness_profile&.preferred_body_focus || @health_profile&.preferred_body_focus).flat_map do |focus|
        BODY_FOCUS_GROUPS.fetch(focus, [])
      end
    end

    def balance_groups_for(primary)
      return %w[chest back] if (primary & LOWER_GROUPS).any?
      return %w[legs core] if (primary & UPPER_GROUPS).any?
      return %w[legs back chest] if primary.empty?

      (UPPER_GROUPS + LOWER_GROUPS).reject { |group| primary.include?(group) }.first(3)
    end

    def cardio_strategy
      enabled = CARDIO_ARCHETYPES.include?(training_archetype) || weight_loss_goal?
      enabled ||= behavior_patterns.include?("skips_cardio")
      {
        "enabled" => enabled,
        "approach" => behavior_patterns.include?("skips_cardio") ? "gradual" : enabled ? "regular" : "optional",
        "sessions_per_week" => enabled ? [ adjusted_frequency / 3, 1 ].max : 0,
        "intensity" => high_risk? ? "low" : intensity_level
      }
    end

    def weight_loss_goal?
      @health_profile&.goal.in?(%w[lose_weight body_definition])
    end

    def strength_strategy
      {
        "enabled" => !CARDIO_ARCHETYPES.include?(training_archetype),
        "sets" => volume_level == "low" ? 2 : volume_level == "high" ? 4 : 3,
        "reps" => training_archetype == "strength_focused" ? 6 : 10,
        "rest_seconds" => training_archetype == "strength_focused" ? 120 : 90,
        "max_exercises_per_session" => adjusted_duration <= SHORT_SESSION_MINUTES ? 5 : 8
      }
    end

    def mobility_strategy
      {
        "enabled" => high_risk? || mobility_goal? || training_archetype == "mobility_focused",
        "focus" => high_risk? ? "controlled_range_and_balance" : "warmup_and_recovery"
      }
    end

    def intensity_level
      return "low" if high_risk? || @fitness_profile&.fitness_level == "beginner"
      return "high" if @health_profile&.intensity_preference == "intense" && @fitness_profile&.fitness_level == "advanced" && risk_score < 5

      "moderate"
    end

    def volume_level
      return "low" if high_risk? || adjusted_duration <= SHORT_SESSION_MINUTES || behavior_patterns.intersect?(%w[low_adherence inconsistent_usage])
      return "high" if @fitness_profile&.fitness_level == "advanced" && @health_profile&.intensity_preference == "intense" && risk_score < 5

      "moderate"
    end

    def progression_model
      return "adaptation" if high_risk? || @fitness_profile&.fitness_level == "beginner" || progress_direction == "insufficient_data"
      return "maintenance" if @fitness_profile&.current_phase == "maintenance" || progress_direction == "stable"
      return "undulating" if @fitness_profile&.fitness_level == "advanced"

      "linear"
    end

    def progress_direction
      agent_result("progress").fetch("progress_direction", "insufficient_data")
    end

    def forbidden_safety_tags
      Array(risk_result["forbidden_exercise_patterns"]).select { |tag| Exercise::SAFETY_TAGS.include?(tag) }.uniq
    end

    def preferred_exercise_ids
      Array(@fitness_profile&.preferred_exercises).filter_map { |id| Integer(id, exception: false) }.uniq
    end

    def avoided_exercise_ids
      Array(@fitness_profile&.avoided_exercises).filter_map { |id| Integer(id, exception: false) }.uniq
    end

    def recommended_patterns
      patterns = Array(risk_result["required_regressions"])
      patterns << "machine_or_supported_variation" if behavior_patterns.include?("prefers_machines") || high_risk?
      patterns << "free_weight_variation" if behavior_patterns.include?("prefers_free_weights") && !high_risk?
      patterns << "short_clear_sessions" if behavior_patterns.include?("consistent_short_sessions")
      patterns << "gradual_cardio_introduction" if behavior_patterns.include?("skips_cardio")
      patterns << "reduced_lower_body_volume" if behavior_patterns.include?("skips_lower_body")
      patterns << "reduced_upper_body_volume" if behavior_patterns.include?("skips_upper_body")
      patterns.uniq
    end

    def generator_notes
      notes = []
      notes << "behavior_overrides_declared_preferences" if behavior_confident? && behavior_patterns.any?
      notes << "filter_forbidden_safety_tags" if forbidden_safety_tags.any?
      notes << "exclude_avoided_exercises" if avoided_exercise_ids.any?
      notes << "prioritize_safe_favorites" if preferred_exercise_ids.any?
      notes << "profile_data_insufficient" unless @fitness_profile
      notes
    end

    def user_facing_explanation
      focus = focus_plan.fetch(:primary).map { |group| group.tr("_", " ") }.first(2).join(" e ")
      split = training_split(adjusted_frequency).tr("_", " ")
      safety = high_risk? ? " com progressão conservadora" : ""
      "Organizamos #{adjusted_frequency} treino#{adjusted_frequency == 1 ? "" : "s"} por semana em #{split}, com foco em #{focus.presence || "um trabalho equilibrado"}#{safety}."
    end
  end
end
