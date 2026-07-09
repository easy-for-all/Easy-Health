class WorkoutPlanGeneratorService
  DAY_SCHEDULE = {
    1 => [ 1 ],
    2 => [1, 4],
    3 => [1, 3, 5],
    4 => [1, 2, 4, 5],
    5 => [1, 2, 3, 4, 5],
    6 => [1, 2, 3, 4, 5, 6]
  }.freeze

  STRENGTH_TEMPLATES = {
    1 => [
      { name: "Full Body",  muscle_groups: %w[chest back legs core] }
    ],
    2 => [
      { name: "Full Body A", muscle_groups: %w[chest back legs] },
      { name: "Full Body B", muscle_groups: %w[shoulders biceps triceps core] }
    ],
    3 => [
      { name: "Full Body A", muscle_groups: %w[chest back legs], emphasis: :compound_first },
      { name: "Full Body B", muscle_groups: %w[shoulders biceps triceps] },
      { name: "Full Body C", muscle_groups: %w[chest back core], emphasis: :accessory_first }
    ],
    4 => [
      { name: "Superior A",  muscle_groups: %w[chest back shoulders], emphasis: :compound_first },
      { name: "Inferior A",  muscle_groups: %w[legs core], emphasis: :compound_first },
      { name: "Superior B",  muscle_groups: %w[biceps triceps chest], emphasis: :accessory_first },
      { name: "Inferior B",  muscle_groups: %w[legs core], emphasis: :accessory_first }
    ],
    5 => [
      { name: "Push",        muscle_groups: %w[chest shoulders triceps], emphasis: :compound_first },
      { name: "Pull",        muscle_groups: %w[back biceps], emphasis: :compound_first },
      { name: "Legs",        muscle_groups: %w[legs core], emphasis: :compound_first },
      { name: "Superior",    muscle_groups: %w[chest back shoulders], emphasis: :accessory_first },
      { name: "Inferior",    muscle_groups: %w[legs core], emphasis: :accessory_first }
    ],
    6 => [
      { name: "Push A",      muscle_groups: %w[chest shoulders triceps], emphasis: :compound_first },
      { name: "Pull A",      muscle_groups: %w[back biceps], emphasis: :compound_first },
      { name: "Legs A",      muscle_groups: %w[legs core], emphasis: :compound_first },
      { name: "Push B",      muscle_groups: %w[chest shoulders triceps], emphasis: :accessory_first },
      { name: "Pull B",      muscle_groups: %w[back biceps], emphasis: :accessory_first },
      { name: "Legs B",      muscle_groups: %w[legs core], emphasis: :accessory_first }
    ]
  }.freeze

  EXPLICIT_SPLITS = {
    "full_body"   => [
      { name: "Full Body", muscle_groups: %w[chest back legs core] }
    ],
    "upper_lower" => [
      { name: "Superior", muscle_groups: %w[chest back shoulders biceps triceps] },
      { name: "Inferior", muscle_groups: %w[legs core] }
    ],
    "ab"          => [
      { name: "Treino A", muscle_groups: %w[chest shoulders triceps] },
      { name: "Treino B", muscle_groups: %w[back biceps legs core] }
    ],
    "abc"         => [
      { name: "Treino A", muscle_groups: %w[chest shoulders triceps] },
      { name: "Treino B", muscle_groups: %w[back biceps] },
      { name: "Treino C", muscle_groups: %w[legs core] }
    ],
    "ppl"         => [
      { name: "Push",  muscle_groups: %w[chest shoulders triceps] },
      { name: "Pull",  muscle_groups: %w[back biceps] },
      { name: "Legs",  muscle_groups: %w[legs core] }
    ]
  }.freeze

  ACTIVITY_NAMES = {
    "cardio"    => "Cardio",
    "hiit"      => "HIIT",
    "funcional" => "Funcional",
    "corrida"   => "Corrida",
    "natacao"   => "Natação",
    "caminhada" => "Caminhada",
    "bicicleta" => "Bike",
    "eliptico"  => "Elíptico",
    "escada"    => "Escada",
    "remo"      => "Remo"
  }.freeze

  SETS_REPS = {
    "beginner"     => { sets: 3, reps: 10, rest_seconds: 90 },
    "intermediate" => { sets: 4, reps: 10, rest_seconds: 75 },
    "advanced"     => { sets: 4, reps: 12, rest_seconds: 60 }
  }.freeze

  EXERCISES_PER_GROUP = 2

  # Non-strategy mode: cap total exercises/day by declared session duration
  # instead of a flat 8, regardless of how much time the user actually has.
  SESSION_DURATION_EXERCISE_CAP = { 15 => 4, 25 => 5, 35 => 6, 45 => 8, 60 => 10 }.freeze

  # Varied weekly schedules by cardio type — up to 6 days, sliced to fit training days
  CARDIO_WEEK_SCHEDULES = {
    "caminhada" => [
      { name: "Caminhada Leve",           exercise_type: "caminhada", duration_minutes: 30, intensity: "leve" },
      { name: "Fortalecimento Funcional", exercise_type: "funcional" },
      { name: "Caminhada Intervalada",    exercise_type: "caminhada", duration_minutes: 25, intensity: "intenso" },
      { name: "Caminhada Moderada",       exercise_type: "caminhada", duration_minutes: 35, intensity: "moderado" },
      { name: "Caminhada Longa",          exercise_type: "caminhada", duration_minutes: 45, intensity: "moderado" },
      { name: "Mobilidade e Recuperação", exercise_type: "funcional" }
    ],
    "corrida" => [
      { name: "Corrida Leve",             exercise_type: "corrida", duration_minutes: 25, intensity: "leve" },
      { name: "Fortalecimento Funcional", exercise_type: "funcional" },
      { name: "Corrida Intervalada",      exercise_type: "corrida", duration_minutes: 20, intensity: "intenso" },
      { name: "Corrida Moderada",         exercise_type: "corrida", duration_minutes: 30, intensity: "moderado" },
      { name: "Corrida Longa",            exercise_type: "corrida", duration_minutes: 40, intensity: "moderado" },
      { name: "Mobilidade e Recuperação", exercise_type: "funcional" }
    ],
    "hiit" => [
      { name: "HIIT Básico",              exercise_type: "hiit", duration_minutes: 20, intensity: "intenso" },
      { name: "Recuperação Ativa",        exercise_type: "caminhada", duration_minutes: 25, intensity: "leve" },
      { name: "HIIT Avançado",            exercise_type: "hiit", duration_minutes: 20, intensity: "intenso" },
      { name: "Funcional Leve",           exercise_type: "funcional" },
      { name: "HIIT Intervalado",         exercise_type: "hiit", duration_minutes: 25, intensity: "intenso" },
      { name: "Recuperação Completa",     exercise_type: "caminhada", duration_minutes: 20, intensity: "leve" }
    ],
    "natacao" => [
      { name: "Natação Leve",             exercise_type: "natacao", duration_minutes: 30, intensity: "leve" },
      { name: "Natação Moderada",         exercise_type: "natacao", duration_minutes: 35, intensity: "moderado" },
      { name: "Natação Intervalada",      exercise_type: "natacao", duration_minutes: 25, intensity: "intenso" },
      { name: "Natação Longa",            exercise_type: "natacao", duration_minutes: 45, intensity: "moderado" },
      { name: "Recuperação Ativa",        exercise_type: "funcional" },
      { name: "Natação de Recuperação",   exercise_type: "natacao", duration_minutes: 20, intensity: "leve" }
    ],
    "cardio" => [
      { name: "Cardio Leve",              exercise_type: "cardio", duration_minutes: 30, intensity: "leve" },
      { name: "Cardio Moderado",          exercise_type: "cardio", duration_minutes: 30, intensity: "moderado" },
      { name: "Cardio Intervalado",       exercise_type: "cardio", duration_minutes: 25, intensity: "intenso" },
      { name: "Cardio Moderado",          exercise_type: "cardio", duration_minutes: 35, intensity: "moderado" },
      { name: "Cardio Longo",             exercise_type: "cardio", duration_minutes: 45, intensity: "moderado" },
      { name: "Recuperação Ativa",        exercise_type: "cardio", duration_minutes: 20, intensity: "leve" }
    ]
  }.freeze

  FUNCIONAL_WEEK_SCHEDULES = [
    { name: "Funcional Completo",    exercise_type: "funcional" },
    { name: "HIIT e Cardio",         exercise_type: "hiit" },
    { name: "Mobilidade e Core",     exercise_type: "funcional" },
    { name: "Funcional Resistência", exercise_type: "funcional" },
    { name: "HIIT Intenso",          exercise_type: "hiit" },
    { name: "Recuperação Ativa",     exercise_type: "caminhada", duration_minutes: 25, intensity: "leve" }
  ].freeze

  attr_reader :plan_rationale

  def initialize(user, days_per_week: nil, activity_preferences: nil,
                 modality: nil, split_type: nil, cardio_type: nil,
                 cardio_format: nil, custom_splits: nil, training_location: nil,
                 chat_decision: nil)
    @user    = user
    @profile = user.health_profile
    @chat_decision = chat_decision
    @fitness_level     = @profile&.fitness_level || "beginner"
    @days_per_week     = @chat_decision ? Array(@chat_decision[:week_structure]).size.clamp(1, 6) : (days_per_week || @profile&.training_days_per_week || 3).clamp(1, 6)
    @modality          = modality          || @profile&.modality          || "ai_choice"
    @split_type        = split_type        || @profile&.split_type        || "ai_choice"
    @cardio_type       = cardio_type       || @profile&.cardio_type       || "cardio"
    @cardio_format     = cardio_format     || @profile&.cardio_format
    @custom_splits     = custom_splits     || @profile&.custom_splits     || []
    @training_location = legacy_training_location(training_location || @profile&.training_location)
    raw_prefs = Array(activity_preferences || @profile&.activity_preferences || [])
    @activity_preferences = raw_prefs.presence || ["musculacao"]
    @plan_rationale    = @chat_decision ? @chat_decision[:rationale] : nil
    @ai_decision       = @chat_decision
    @ai_sets_reps      = @chat_decision ? @chat_decision[:sets_reps] : nil
    @fitness_profile   = user.fitness_profile
  end

  def call
    @workout_strategy = build_workout_strategy
    @strategy_active = @chat_decision ? false : FitnessIntelligence.enabled?
    old_favorited_names = @user.active_workout_plan
                            &.workout_days&.where(favorited: true)&.pluck(:name) || []
    fav_exercise_ids = if @strategy_active
      Array(@workout_strategy["preferred_exercises"])
    else
      @user.user_favorite_exercises.pluck(:exercise_id)
    end
    @candidate_scope = WorkoutIntelligence::ExerciseCandidateScope.new(
      training_location: @training_location,
      fitness_level: @fitness_level,
      strategy: @strategy_active ? @workout_strategy : nil,
      available_equipment: Array(@profile&.available_equipment || @fitness_profile&.available_equipment),
      fav_exercise_ids: fav_exercise_ids
    )

    plan_days_per_week = @strategy_active ? strategy_frequency : @days_per_week
    template = @strategy_active ? build_strategy_template : build_template
    schedule = DAY_SCHEDULE[plan_days_per_week]
    @goal = @profile&.goal

    group_occurrences = template.each_with_object(Hash.new(0)) do |day_tmpl, counts|
      Array(day_tmpl[:muscle_groups]).each { |group| counts[group] += 1 }
    end
    @volume_planner = WorkoutIntelligence::WeeklyVolumePlanner.new(
      goal: @goal,
      fitness_level: @fitness_level,
      days_per_week: plan_days_per_week,
      session_duration_minutes: @profile&.session_duration_minutes,
      preferred_body_focus: @profile&.preferred_body_focus,
      groups_in_template: group_occurrences.keys
    )
    @volume_planner.call
    @day_variation_selector = WorkoutIntelligence::DayVariationSelector.new(
      fitness_level: @fitness_level,
      style_tags: Array(@profile&.preferred_training_styles)
    )
    @top_up_filler = WorkoutIntelligence::TopUpFiller.new
    @exercises_used_this_week = Set.new
    WorkoutIntelligence::DecisionLogger.log(
      event: "plan_generation_started", user_id: @user.id,
      goal: WorkoutIntelligence::GoalTrainingProfile.normalize_goal(@goal), fitness_level: @fitness_level,
      days_per_week: plan_days_per_week, weekly_volume_targets: @volume_planner.targets,
      decision_source: @ai_decision ? "ai" : (@strategy_active ? "strategy" : "rule_based")
    )

    plan = nil
    WorkoutPlan.transaction do
      @user.workout_plans.update_all(active: false)
      plan = @user.workout_plans.create!(active: true)
      persist_workout_strategy(plan)
      @profile&.update_columns(
        training_days_per_week: @days_per_week,
        activity_preferences:   @activity_preferences
      )

      template.each_with_index do |day_tmpl, idx|
        day = plan.workout_days.create!(
          day_of_week: schedule[idx],
          name:        day_tmpl[:name],
          position:    idx + 1
        )

        idx_exercise = 0

        if day_tmpl[:exercise_type]
          ex_type   = day_tmpl[:exercise_type]
          exercises = @candidate_scope.for_exercise_type(ex_type)
                        .where.not(id: @exercises_used_this_week.to_a.presence || [ 0 ])
                        .limit(day_exercise_limit)

          # Outdoor funcional fallback: gym-equipment funcional exercises are filtered out,
          # so complement with HIIT bodyweight exercises
          if exercises.empty? && ex_type == "funcional" && @training_location == "outdoor"
            exercises = @candidate_scope.base_relation.where(exercise_type: %w[funcional hiit])
                          .where.not(id: @exercises_used_this_week.to_a.presence || [ 0 ])
                          .limit(day_exercise_limit)
          end

          exercises.each do |ex|
            is_cardio = WorkoutDayExercise::CARDIO_TYPES.include?(ex.exercise_type)
            attrs = { exercise: ex, order_index: idx_exercise }
            if is_cardio
              attrs[:duration_minutes] = day_tmpl[:duration_minutes] || 30
              attrs[:intensity]        = day_tmpl[:intensity] || "moderado"
              attrs[:rest_seconds]     = 0
            else
              params = exercise_training_params(ex)
              attrs[:sets]         = params[:sets]
              attrs[:reps]         = params[:reps]
              attrs[:rest_seconds] = params[:rest_seconds]
            end
            day.workout_day_exercises.create!(**attrs)
            @exercises_used_this_week << ex.id
            idx_exercise += 1
          end
        else
          day_tmpl[:muscle_groups].each do |group|
            break if idx_exercise >= day_exercise_limit

            occurrences = group_occurrences[group]
            target      = @volume_planner.exercise_count(group: group, occurrences_in_week: occurrences)
            group_limit = [ target, day_exercise_limit - idx_exercise ].min
            next if group_limit <= 0

            picked = @day_variation_selector.select(
              scope: @candidate_scope.for_group(group),
              group: group,
              count: group_limit,
              exclude_ids: @exercises_used_this_week,
              emphasis: day_tmpl[:emphasis] || :balanced
            )

            if picked.size < group_limit
              picked = @top_up_filler.fill(
                current_exercises: picked,
                target_count: group_limit,
                primary_group: group,
                base_scope: @candidate_scope.base_relation,
                exclude_ids: @exercises_used_this_week
              )
            end

            if picked.empty?
              WorkoutIntelligence::DecisionLogger.log(event: "group_exercises_unavailable", user_id: @user.id, group: group, day: day_tmpl[:name])
            end

            picked.each do |ex|
              params = exercise_training_params(ex)
              day.workout_day_exercises.create!(
                exercise: ex, sets: params[:sets], reps: params[:reps],
                rest_seconds: params[:rest_seconds], order_index: idx_exercise
              )
              @exercises_used_this_week << ex.id
              idx_exercise += 1
            end
          end
        end
      end

      @plan_validation = WorkoutIntelligence::PlanValidator.new(
        plan: plan, health_profile: @profile, fitness_level: @fitness_level, goal: @goal,
        weekly_volume_targets: @volume_planner.targets, candidate_scope: @candidate_scope,
        decision_source: decision_source_label
      ).call
      WorkoutIntelligence::DecisionLogger.log(
        event: "plan_validated", user_id: @user.id, plan_id: plan.id,
        valid: @plan_validation.valid, violations: @plan_validation.violations,
        warnings: @plan_validation.warnings, auto_fixes: @plan_validation.auto_fixes
      )
      if @plan_validation.violations.any? { |v| v[:fatal] }
        raise @plan_validation.violations.map { |v| v[:message] }.join("; ")
      end

      plan.workout_days.where(name: old_favorited_names).update_all(favorited: true) if old_favorited_names.any?
    end

    persist_training_decision_log_safely(plan, template)
    update_adherence_score_safely

    plan
  end

  def plan_summary
    primary_cardio = ACTIVITY_NAMES.fetch(@cardio_type, "Cardio")
    fmt = format_description

    case @modality
    when "cardio"
      base = "Criamos um plano focado em #{primary_cardio.downcase}"
      base += " ao ar livre" if @training_location == "outdoor"
      base += "#{fmt}para evoluir gradualmente no seu condicionamento cardiovascular."
      base
    when "funcional"
      loc = case @training_location
            when "home"    then " em casa"
            when "outdoor" then " ao ar livre"
            else ""
            end
      "Criamos um plano funcional#{loc} com exercícios de peso corporal, mobilidade e HIIT para melhorar o desempenho no dia a dia."
    when "misto"
      "Criamos um plano misto combinando musculação e #{primary_cardio.downcase}#{fmt}para equilíbrio entre força e condicionamento."
    else
      wants_strength = @activity_preferences.include?("musculacao")
      non_strength   = @activity_preferences - ["musculacao"]
      if !wants_strength && non_strength.any?
        primary = ACTIVITY_NAMES.fetch(non_strength.first, "Cardio")
        "Montamos um plano de #{primary.downcase}#{fmt}com progressão de intensidade e fortalecimento complementar."
      else
        split_name = @split_type == "ai_choice" ? "selecionada pela IA" : @split_type.upcase
        "Como você escolheu musculação, criamos uma divisão #{split_name} para ganho de força e consistência."
      end
    end
  end

  private

  def build_workout_strategy
    if strategy_profile_stale?
      @fitness_profile = FitnessIntelligence::ProfileBuilder.new(@user).call(source: "workout_plan_strategy")
    end
    CoachEngine::WorkoutStrategist.new(
      user: @user,
      fitness_profile: @fitness_profile,
      health_profile: @profile
    ).call
  rescue StandardError => e
    Rails.logger.error("[WorkoutPlanGeneratorService] Workout strategy failed: #{e.class}: #{e.message}")
    CoachEngine::WorkoutStrategist.new(
      user: @user,
      fitness_profile: @user.fitness_profile,
      health_profile: @profile
    ).call
  end

  def strategy_profile_stale?
    return false unless @profile
    return true unless @fitness_profile

    @fitness_profile.last_recalculated_at.blank? || @fitness_profile.last_recalculated_at < @profile.updated_at
  end

  def persist_workout_strategy(plan)
    WorkoutStrategy.create!(
      user: @user,
      workout_plan: plan,
      fitness_profile: @fitness_profile,
      strategy: @workout_strategy,
      strategy_version: @workout_strategy.fetch("strategy_version", WorkoutStrategy::VERSION)
    )
  end

  # goal/level-aware sets/reps/rest for a single exercise, distinguishing
  # compound (main lift) from accessory work — replaces the old flat
  # per-day `params` that applied the same prescription to every exercise
  # regardless of goal.
  def exercise_training_params(exercise)
    return @ai_sets_reps if @ai_sets_reps

    role = WorkoutIntelligence::ExerciseRoleClassifier.role_for(exercise)
    WorkoutIntelligence::GoalTrainingProfile.for(goal: @goal, fitness_level: @fitness_level, role: role)
  end

  def strategy_frequency
    @workout_strategy.fetch("weekly_frequency", @days_per_week).to_i.clamp(1, 6)
  end

  def decision_source_label
    return "ai" if @ai_decision
    return "strategy" if @strategy_active

    "rule_based"
  end

  def day_exercise_limit
    return @workout_strategy.dig("strength_strategy", "max_exercises_per_session").to_i.clamp(1, 12) if @strategy_active

    SESSION_DURATION_EXERCISE_CAP.fetch(@profile&.session_duration_minutes, EXERCISES_PER_GROUP * 4)
  end

  def build_template
    return Array(@chat_decision[:week_structure]).first(@days_per_week) if @chat_decision
    return build_custom_template   if @split_type == "custom"
    return build_explicit_template if EXPLICIT_SPLITS.key?(@split_type)
    build_ai_driven_template || build_ai_template
  end

  def build_strategy_template
    split = @workout_strategy.fetch("training_split", "full_body")
    priority = Array(@workout_strategy["body_focus_priority"])
    upper = priority & %w[chest back shoulders biceps triceps]
    lower = priority & %w[legs glutes calves]
    upper = %w[chest back shoulders] if upper.empty?
    lower = %w[legs core] if lower.empty?

    case split
    when "cardio_mobility"
      build_cardio_mobility_template
    when "abc"
      [
        { name: "Treino A", muscle_groups: upper.first(3) },
        { name: "Treino B", muscle_groups: (upper.drop(3).presence || %w[back biceps]) },
        { name: "Treino C", muscle_groups: (lower + [ "core" ]).uniq }
      ].cycle.take(strategy_frequency)
    when "upper_lower"
      [
        { name: "Superior", muscle_groups: upper },
        { name: "Inferior", muscle_groups: (lower + [ "core" ]).uniq }
      ].cycle.take(strategy_frequency)
    when "push_pull_legs"
      [
        { name: "Push", muscle_groups: upper & %w[chest shoulders triceps] },
        { name: "Pull", muscle_groups: upper & %w[back biceps] },
        { name: "Legs", muscle_groups: (lower + [ "core" ]).uniq }
      ].cycle.take(strategy_frequency).map { |day| day.merge(muscle_groups: day[:muscle_groups].presence || upper.first(3)) }
    else
      full_body_groups = (priority + [ "core" ]).uniq.first(5)
      Array.new(strategy_frequency) { |index| { name: "Full Body #{index + 1}", muscle_groups: full_body_groups } }
    end
  end

  def build_cardio_mobility_template
    cardio_enabled = @workout_strategy.dig("cardio_strategy", "enabled")
    Array.new(strategy_frequency) do |index|
      cardio_day = cardio_enabled && index.even?
      {
        name: cardio_day ? "Cardio Progressivo" : "Mobilidade e Core",
        exercise_type: cardio_day ? "cardio" : "funcional"
      }
    end
  end

  def build_ai_driven_template
    # Only use AI for musculacao/ai_choice modalities — rule-based handles cardio/funcional well
    return nil unless %w[musculacao ai_choice].include?(@modality)

    if AiWorkout::DailyLimitChecker.new(@user).limit_reached?
      Rails.logger.info("[WorkoutPlanGeneratorService] Daily AI limit reached for user #{@user.id}")
      return nil
    end

    fav_ids = @user.user_favorite_exercises.pluck(:exercise_id)
    avail   = available_exercises_by_group

    prebuilt_prompt, prompt_version_id = build_ai_workout_prompt(fav_ids, avail)

    planner = AiAgents::WorkoutPlannerService.new(
      @user,
      days_per_week:       @days_per_week,
      profile:             @profile,
      fav_exercise_ids:    fav_ids,
      available_exercises: avail,
      prebuilt_prompt:     prebuilt_prompt
    )

    raw_decision = planner.call
    return nil unless raw_decision

    decision = apply_ai_workout_pipeline(raw_decision, prompt_version_id)
    return nil unless decision

    @ai_decision    = decision
    @plan_rationale = decision[:rationale]

    ai_params = decision[:sets_reps]
    if ai_params
      @ai_sets_reps = {
        sets:         ai_params[:sets].clamp(1, 6),
        reps:         ai_params[:reps].clamp(1, 30),
        rest_seconds: ai_params[:rest_seconds].clamp(0, 300)
      }
    end

    decision[:week_structure].first(@days_per_week)
  rescue => e
    Rails.logger.error("[WorkoutPlanGeneratorService] AI template failed: #{e.message}")
    nil
  end

  def build_ai_workout_prompt(fav_ids, avail)
    return [nil, nil] unless @strategy_active && @fitness_profile

    strategy_record = @fitness_profile.workout_strategies.order(created_at: :desc).first

    result = AiWorkout::PromptBuilder.new(
      user:               @user,
      fitness_profile:    @fitness_profile,
      workout_strategy:   strategy_record,
      days_per_week:      @days_per_week,
      fav_exercise_ids:   fav_ids,
      available_exercises: avail
    ).call

    [result[:prompt], result[:prompt_version_id]]
  end

  def apply_ai_workout_pipeline(raw_decision, prompt_version_id)
    if @strategy_active && @fitness_profile
      safety_result = AiWorkout::SafetyValidator.new(
        parsed_data:      raw_decision,
        fitness_profile:  @fitness_profile,
        workout_strategy: @fitness_profile.workout_strategies.order(created_at: :desc).first
      ).call

      unless safety_result[:valid]
        Rails.logger.warn("[WorkoutPlanGeneratorService] Safety violations: #{safety_result[:violations].join(', ')}")
        UserEventService.track(
          user:     @user,
          event:    :ai_workout_validation_failed,
          metadata: { violations: safety_result[:violations] }
        )
        return nil
      end

      safety_result[:warnings].each do |w|
        Rails.logger.info("[WorkoutPlanGeneratorService] Safety warning: #{w}")
      end

      @ai_prompt_version_id = prompt_version_id
    end

    UserEventService.track(
      user:     @user,
      event:    :ai_workout_generated,
      metadata: {
        training_method:   raw_decision[:training_method],
        prompt_version_id: prompt_version_id
      }
    )
    raw_decision
  end

  def available_exercises_by_group
    @candidate_scope.for_exercise_type("musculacao").reorder(nil).group(:muscle_group).count
  end

  def build_explicit_template
    base = EXPLICIT_SPLITS[@split_type]

    case @modality
    when "cardio"
      build_cardio_week_template(resolved_cardio_type)
    when "funcional"
      build_funcional_template
    when "misto"
      build_misto_template
    else
      base.cycle.take(@days_per_week)
    end
  end

  def build_ai_template
    # Explicit modality takes priority — honor what the user selected
    return build_cardio_week_template(resolved_cardio_type) if @modality == "cardio"
    return build_funcional_template                          if @modality == "funcional"
    return build_misto_template                              if @modality == "misto"

    # For musculacao / ai_choice: use activity_preferences to decide
    non_strength   = (@activity_preferences - ["musculacao"]).uniq
    wants_strength = @activity_preferences.include?("musculacao")

    # No strength preference → build cardio/functional plan
    unless wants_strength
      primary = non_strength.first || resolved_cardio_type
      return build_cardio_week_template(primary)
    end

    # Strength as base with optional cardio/functional days
    strength_count = [[@days_per_week - non_strength.size, 1].max, 6].min
    strength_days  = (STRENGTH_TEMPLATES[strength_count] || STRENGTH_TEMPLATES[3]).dup
    other_days     = non_strength.map do |t|
      schedule = CARDIO_WEEK_SCHEDULES[t] || CARDIO_WEEK_SCHEDULES["cardio"]
      schedule.first
    end
    (strength_days + other_days).first(@days_per_week)
  end

  def build_funcional_template
    FUNCIONAL_WEEK_SCHEDULES.first(@days_per_week)
  end

  def build_misto_template
    return STRENGTH_TEMPLATES.fetch(1) if @days_per_week == 1

    strength_count  = [(@days_per_week * 2 / 3.0).ceil, @days_per_week - 1].min
    cardio_count    = @days_per_week - strength_count
    strength_days   = (STRENGTH_TEMPLATES[strength_count] || STRENGTH_TEMPLATES[3]).dup
    cardio_schedule = CARDIO_WEEK_SCHEDULES[resolved_cardio_type] || CARDIO_WEEK_SCHEDULES["cardio"]
    cardio_days     = cardio_schedule.first(cardio_count)
    strength_days + cardio_days
  end

  def build_cardio_week_template(cardio_key = nil)
    key = cardio_key.presence || resolved_cardio_type
    key = "cardio" unless CARDIO_WEEK_SCHEDULES.key?(key)
    schedule = CARDIO_WEEK_SCHEDULES[key].dup
    schedule = apply_cardio_format(schedule)
    schedule.first(@days_per_week)
  end

  def apply_cardio_format(schedule)
    return schedule unless @cardio_format

    case @cardio_format
    when "progressivo"
      # Sort light → functional/no-intensity → moderate → intense (gradual build-up)
      intensity_rank = { "leve" => 0, nil => 1, "moderado" => 2, "intenso" => 3 }
      schedule.sort_by { |d| intensity_rank.fetch(d[:intensity], 1) }
    when "continuo_leve"
      # Light sessions first
      schedule.sort_by { |d| d[:intensity] == "leve" ? 0 : 1 }
    when "continuo_moderado"
      # Moderate sessions first
      schedule.sort_by { |d| d[:intensity] == "moderado" ? 0 : 1 }
    when "intervalado", "hiit"
      # Alternate intense and easy sessions
      intense = schedule.select { |d| d[:intensity] == "intenso" }
      easy    = schedule.reject { |d| d[:intensity] == "intenso" }
      result  = []
      [intense.size, easy.size].max.times do |i|
        result << intense[i] if intense[i]
        result << easy[i]    if easy[i]
      end
      result
    when "recuperacao"
      # Light sessions first, intense last
      schedule.sort_by { |d| d[:intensity] == "leve" ? 0 : 1 }
    else
      schedule
    end
  end

  def build_custom_template
    return build_ai_template if @custom_splits.blank?

    @custom_splits.first(@days_per_week).map do |split|
      {
        name:          split["name"] || "Treino",
        muscle_groups: Array(split["muscle_groups"])
      }
    end
  end

  def legacy_training_location(location)
    {
      "full_gym" => "gym",
      "simple_gym" => "gym",
      "home" => "home",
      "condo" => "home",
      "hotel_travel" => "home",
      "outdoor" => "outdoor",
      "unknown" => "any",
      "gym" => "gym",
      "any" => "any"
    }.fetch(location, "gym")
  end

  def persist_training_decision_log_safely(plan, template)
    decision = @ai_decision || WorkoutIntelligence::PlanRationaleBuilder.new(
      health_profile: @profile, fitness_level: @fitness_level, goal: @goal,
      template: template, weekly_volume_targets: @volume_planner.targets,
      validation: @plan_validation, decision_source: decision_source_label
    ).call

    AiTrainingDecisionLog.create!(
      user:                   @user,
      workout_plan:           plan,
      decision_source:        decision_source_label,
      training_method:        decision[:training_method],
      rationale:              decision[:rationale],
      progression_strategy:   decision[:progression_strategy],
      safety_notes:           decision[:safety_notes],
      week_structure:         decision[:week_structure].map { |d| { name: d[:name], muscle_groups: d[:muscle_groups] } },
      model_used:             @ai_decision ? AiConfig.for(@chat_decision ? :workout_chat_plan_generation : :workout_planning)[:model] : "workout_intelligence_v1",
      prompt_version_id:      @ai_prompt_version_id,
      generation_type:        "workout_plan",
      status:                 "success",
      output_summary:         {
        personalization_reason: decision[:personalization_reason],
        user_explanation:       decision[:user_explanation],
        coach_notes:            decision[:coach_notes],
        plan_name:              decision[:plan_name]
      },
      input_summary:          {
        fitness_level:          @fitness_level,
        days_per_week:          @days_per_week,
        modality:               @modality,
        training_location:      @training_location,
        goal:                   @profile&.goal,
        primary_persona:        @fitness_profile&.primary_persona,
        training_archetype:     @fitness_profile&.training_archetype,
        behavior_pattern:       @fitness_profile&.behavior_pattern
      }
    )
  rescue => e
    Rails.logger.error("[WorkoutPlanGeneratorService] Failed to persist training decision log: #{e.message}")
  end

  def update_adherence_score_safely
    return unless @profile

    sessions_last_30 = @user.workout_sessions
      .where(completed_at: 30.days.ago..)
      .count
    expected = (@days_per_week * 4.3).round
    score    = expected.positive? ? [(sessions_last_30.to_f / expected * 100).round(2), 100.0].min : nil

    @profile.update_columns(
      adherence_score:        score,
      last_profile_review_at: Time.current
    )
  rescue => e
    Rails.logger.error("[WorkoutPlanGeneratorService] Failed to update adherence score: #{e.message}")
  end

  def resolved_cardio_type
    case @cardio_type
    when "bicicleta", "eliptico", "escada", "remo" then "cardio"
    when "corrida"                                  then "corrida"
    when "caminhada"                                then "caminhada"
    when "natacao"                                  then "natacao"
    when "hiit"                                     then "hiit"
    else "cardio"
    end
  end

  def format_description
    case @cardio_format
    when "progressivo"       then " com progressão gradual de intensidade, "
    when "intervalado"       then " alternando entre esforço intenso e recuperação, "
    when "continuo_leve"     then " em ritmo leve e constante, "
    when "continuo_moderado" then " em ritmo moderado e constante, "
    when "hiit"              then " com treinos curtos de alta intensidade, "
    when "recuperacao"       then " com foco em recuperação ativa e baixo impacto, "
    else                          " "
    end
  end
end
