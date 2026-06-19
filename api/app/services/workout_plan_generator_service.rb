class WorkoutPlanGeneratorService
  DAY_SCHEDULE = {
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
      { name: "Full Body A", muscle_groups: %w[chest back legs] },
      { name: "Full Body B", muscle_groups: %w[shoulders biceps triceps] },
      { name: "Full Body C", muscle_groups: %w[chest back core] }
    ],
    4 => [
      { name: "Superior A",  muscle_groups: %w[chest back shoulders] },
      { name: "Inferior A",  muscle_groups: %w[legs core] },
      { name: "Superior B",  muscle_groups: %w[biceps triceps chest] },
      { name: "Inferior B",  muscle_groups: %w[legs core] }
    ],
    5 => [
      { name: "Push",        muscle_groups: %w[chest shoulders triceps] },
      { name: "Pull",        muscle_groups: %w[back biceps] },
      { name: "Legs",        muscle_groups: %w[legs core] },
      { name: "Superior",    muscle_groups: %w[chest back shoulders] },
      { name: "Inferior",    muscle_groups: %w[legs core] }
    ],
    6 => [
      { name: "Push A",      muscle_groups: %w[chest shoulders triceps] },
      { name: "Pull A",      muscle_groups: %w[back biceps] },
      { name: "Legs A",      muscle_groups: %w[legs core] },
      { name: "Push B",      muscle_groups: %w[chest shoulders triceps] },
      { name: "Pull B",      muscle_groups: %w[back biceps] },
      { name: "Legs B",      muscle_groups: %w[legs core] }
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

  # Equipment types that work outdoors (no gym machines needed)
  OUTDOOR_COMPATIBLE_EQUIPMENT = %w[bodyweight cardio].freeze

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
                 cardio_format: nil, custom_splits: nil, training_location: nil)
    @user    = user
    @profile = user.health_profile
    @fitness_level     = @profile&.fitness_level || "beginner"
    @days_per_week     = (days_per_week || @profile&.training_days_per_week || 3).clamp(2, 6)
    @modality          = modality          || @profile&.modality          || "ai_choice"
    @split_type        = split_type        || @profile&.split_type        || "ai_choice"
    @cardio_type       = cardio_type       || @profile&.cardio_type       || "cardio"
    @cardio_format     = cardio_format     || @profile&.cardio_format
    @custom_splits     = custom_splits     || @profile&.custom_splits     || []
    @training_location = training_location || @profile&.training_location || "gym"
    raw_prefs = Array(activity_preferences || @profile&.activity_preferences || [])
    @activity_preferences = raw_prefs.presence || ["musculacao"]
    @plan_rationale    = nil
    @ai_decision       = nil
  end

  def call
    WorkoutPlan.transaction do
      old_favorited_names = @user.active_workout_plan
                              &.workout_days&.where(favorited: true)&.pluck(:name) || []
      fav_exercise_ids = @user.user_favorite_exercises.pluck(:exercise_id)

      @user.workout_plans.update_all(active: false)
      plan = @user.workout_plans.create!(active: true)
      @profile&.update_columns(
        training_days_per_week: @days_per_week,
        activity_preferences:   @activity_preferences
      )

      template = build_template
      schedule = DAY_SCHEDULE[@days_per_week]
      params   = @ai_sets_reps || SETS_REPS[@fitness_level]

      template.each_with_index do |day_tmpl, idx|
        day = plan.workout_days.create!(
          day_of_week: schedule[idx],
          name:        day_tmpl[:name],
          position:    idx + 1
        )

        idx_exercise = 0

        if day_tmpl[:exercise_type]
          ex_type   = day_tmpl[:exercise_type]
          exercises = exercise_scope(Exercise.where(exercise_type: ex_type), fav_exercise_ids).limit(EXERCISES_PER_GROUP * 2)

          # Outdoor funcional fallback: gym-equipment funcional exercises are filtered out,
          # so complement with HIIT bodyweight exercises
          if exercises.empty? && ex_type == "funcional" && @training_location == "outdoor"
            exercises = exercise_scope(
              Exercise.where(exercise_type: %w[funcional hiit]),
              fav_exercise_ids
            ).limit(EXERCISES_PER_GROUP * 2)
          end

          exercises.each do |ex|
            is_cardio = WorkoutDayExercise::CARDIO_TYPES.include?(ex.exercise_type)
            attrs = { exercise: ex, order_index: idx_exercise }
            if is_cardio
              attrs[:duration_minutes] = day_tmpl[:duration_minutes] || 30
              attrs[:intensity]        = day_tmpl[:intensity] || "moderado"
              attrs[:rest_seconds]     = 0
            else
              attrs[:sets]         = params[:sets]
              attrs[:reps]         = params[:reps]
              attrs[:rest_seconds] = params[:rest_seconds]
            end
            day.workout_day_exercises.create!(**attrs)
            idx_exercise += 1
          end
        else
          day_tmpl[:muscle_groups].each do |group|
            exercise_scope(Exercise.where(exercise_type: "musculacao", muscle_group: group), fav_exercise_ids)
                    .limit(EXERCISES_PER_GROUP).each do |ex|
              day.workout_day_exercises.create!(
                exercise: ex, sets: params[:sets], reps: params[:reps],
                rest_seconds: params[:rest_seconds], order_index: idx_exercise
              )
              idx_exercise += 1
            end
          end
        end
      end

      raise "Workout plan was not generated" if plan.workout_days.empty?
      total_exercises = plan.workout_days.sum { |d| d.workout_day_exercises.count }
      raise "No exercises found — run db:seed in production" if total_exercises.zero?

      plan.workout_days.where(name: old_favorited_names).update_all(favorited: true) if old_favorited_names.any?

      persist_ai_decision_log(plan) if @ai_decision
      update_adherence_score

      plan
    end
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

  def build_template
    return build_custom_template   if @split_type == "custom"
    return build_explicit_template if EXPLICIT_SPLITS.key?(@split_type)
    build_ai_driven_template || build_ai_template
  end

  def build_ai_driven_template
    # Only use AI for musculacao/ai_choice modalities — rule-based handles cardio/funcional well
    return nil unless %w[musculacao ai_choice].include?(@modality)

    fav_ids    = @user.user_favorite_exercises.pluck(:exercise_id)
    avail      = available_exercises_by_group

    planner = AiAgents::WorkoutPlannerService.new(
      @user,
      days_per_week:       @days_per_week,
      profile:             @profile,
      fav_exercise_ids:    fav_ids,
      available_exercises: avail
    )

    decision = planner.call
    return nil unless decision

    @ai_decision    = decision
    @plan_rationale = decision[:rationale]

    # Override sets/reps/rest with AI recommendation
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

  def available_exercises_by_group
    scope = Exercise.where(exercise_type: "musculacao")
    scope = scope.where(home_compatible: true)   if @training_location == "home"
    scope = scope.where(equipment_type: OUTDOOR_COMPATIBLE_EQUIPMENT) if @training_location == "outdoor"

    scope.group(:muscle_group).count
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

  def exercise_scope(relation, fav_ids = [])
    rel = case @training_location
          when "home"    then relation.where(home_compatible: true)
          when "outdoor" then relation.where(equipment_type: OUTDOOR_COMPATIBLE_EQUIPMENT)
          else relation
          end

    rel = rel.merge(Exercise.browseable)

    fav_priority = if fav_ids.any?
      Arel.sql("CASE WHEN id IN (#{fav_ids.map(&:to_i).join(',')}) THEN 0 ELSE 1 END")
    else
      Arel.sql("1")
    end

    rel.order(fav_priority, Arel.sql("CASE WHEN gif_url IS NOT NULL THEN 0 ELSE 1 END"), :id)
  end

  def persist_ai_decision_log(plan)
    AiTrainingDecisionLog.create!(
      user:                @user,
      workout_plan:        plan,
      training_method:     @ai_decision[:training_method],
      rationale:           @ai_decision[:rationale],
      progression_strategy: @ai_decision[:progression_strategy],
      safety_notes:        @ai_decision[:safety_notes],
      week_structure:      @ai_decision[:week_structure].map { |d| { name: d[:name], muscle_groups: d[:muscle_groups] } },
      model_used:          AiConfig.for(:workout_planning)[:model],
      input_summary:       {
        fitness_level:     @fitness_level,
        days_per_week:     @days_per_week,
        modality:          @modality,
        training_location: @training_location,
        goal:              @profile&.goal
      }
    )
  rescue => e
    Rails.logger.error("[WorkoutPlanGeneratorService] Failed to persist AI decision log: #{e.message}")
  end

  def update_adherence_score
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
