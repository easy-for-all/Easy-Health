class WorkoutPlanGeneratorService
  DAY_SCHEDULE = {
    2 => [1, 4],
    3 => [1, 3, 5],
    4 => [1, 2, 4, 5],
    5 => [1, 2, 3, 4, 5],
    6 => [1, 2, 3, 4, 5, 6]
  }.freeze

  # Used by ai_choice mode (based on number of strength days)
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

  # Explicit split base templates (cycled to fill training days)
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
  end

  def call
    WorkoutPlan.transaction do
      @user.workout_plans.update_all(active: false)
      plan = @user.workout_plans.create!(active: true)
      @profile&.update_columns(
        training_days_per_week: @days_per_week,
        activity_preferences:   @activity_preferences
      )

      template = build_template
      schedule = DAY_SCHEDULE[@days_per_week]
      params   = SETS_REPS[@fitness_level]

      template.each_with_index do |day_tmpl, idx|
        day = plan.workout_days.create!(
          day_of_week: schedule[idx],
          name:        day_tmpl[:name],
          position:    idx + 1
        )

        idx_exercise = 0

        if day_tmpl[:exercise_type]
          exercises = exercise_scope(Exercise.where(exercise_type: day_tmpl[:exercise_type])).limit(EXERCISES_PER_GROUP * 2)
          exercises.each do |ex|
            day.workout_day_exercises.create!(
              exercise: ex, sets: params[:sets], reps: params[:reps],
              rest_seconds: params[:rest_seconds], order_index: idx_exercise
            )
            idx_exercise += 1
          end
        else
          day_tmpl[:muscle_groups].each do |group|
            exercise_scope(Exercise.where(exercise_type: "musculacao", muscle_group: group))
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

      plan
    end
  end

  private

  def build_template
    return build_custom_template   if @split_type == "custom"
    return build_explicit_template if EXPLICIT_SPLITS.key?(@split_type)
    build_ai_template
  end

  def build_explicit_template
    base = EXPLICIT_SPLITS[@split_type]

    case @modality
    when "cardio"
      @days_per_week.times.map do |i|
        { name: "#{ACTIVITY_NAMES.fetch(@cardio_type, "Cardio")} #{i + 1}", exercise_type: resolved_cardio_type }
      end
    when "misto"
      strength_count = [(@days_per_week * 2 / 3.0).ceil, @days_per_week - 1].min
      cardio_count   = @days_per_week - strength_count
      strength_days  = base.cycle.take(strength_count)
      cardio_days    = cardio_count.times.map do |i|
        { name: "#{ACTIVITY_NAMES.fetch(@cardio_type, "Cardio")} #{i + 1}", exercise_type: resolved_cardio_type }
      end
      strength_days + cardio_days
    else
      base.cycle.take(@days_per_week)
    end
  end

  def build_ai_template
    other_types    = (@activity_preferences - ["musculacao"]).uniq
    strength_count = [[@days_per_week - other_types.size, 1].max, 6].min

    strength_days = (STRENGTH_TEMPLATES[strength_count] || STRENGTH_TEMPLATES[3]).dup
    other_days    = other_types.map { |t| { name: ACTIVITY_NAMES.fetch(t, t.capitalize), exercise_type: t } }

    (strength_days + other_days).first(@days_per_week)
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

  def exercise_scope(relation)
    return relation.where(equipment_type: "bodyweight") if @training_location == "home"
    relation
  end

  # Resolve cardio_type to an exercise_type that exists in the DB
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
end
