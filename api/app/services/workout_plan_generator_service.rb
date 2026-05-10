class WorkoutPlanGeneratorService
  # Internal weekday assignments by total days (0=Sun, 1=Mon ... 6=Sat)
  DAY_SCHEDULE = {
    2 => [1, 4],
    3 => [1, 3, 5],
    4 => [1, 2, 4, 5],
    5 => [1, 2, 3, 4, 5],
    6 => [1, 2, 3, 4, 5, 6]
  }.freeze

  # Strength splits indexed by number of strength days
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

  ACTIVITY_NAMES = {
    "cardio"    => "Cardio",
    "hiit"      => "HIIT",
    "funcional" => "Funcional",
    "corrida"   => "Corrida",
    "natacao"   => "Natação",
    "caminhada" => "Caminhada"
  }.freeze

  SETS_REPS = {
    "beginner"     => { sets: 3, reps: 10, rest_seconds: 90 },
    "intermediate" => { sets: 4, reps: 10, rest_seconds: 75 },
    "advanced"     => { sets: 4, reps: 12, rest_seconds: 60 }
  }.freeze

  EXERCISES_PER_GROUP = 2

  def initialize(user, days_per_week: nil, activity_preferences: nil)
    @user    = user
    @profile = user.health_profile
    @fitness_level = @profile&.fitness_level || "beginner"
    @days_per_week = (days_per_week || @profile&.training_days_per_week || 3).clamp(2, 6)
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
          # Non-strength day: pick exercises by type
          exercises = Exercise.where(exercise_type: day_tmpl[:exercise_type]).limit(EXERCISES_PER_GROUP * 2)
          exercises.each do |ex|
            day.workout_day_exercises.create!(
              exercise: ex, sets: params[:sets], reps: params[:reps],
              rest_seconds: params[:rest_seconds], order_index: idx_exercise
            )
            idx_exercise += 1
          end
        else
          # Strength day: pick exercises by muscle group
          day_tmpl[:muscle_groups].each do |group|
            Exercise.where(exercise_type: "musculacao", muscle_group: group)
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
    other_types    = (@activity_preferences - ["musculacao"]).uniq
    strength_count = [[@days_per_week - other_types.size, 1].max, 6].min

    strength_days = (STRENGTH_TEMPLATES[strength_count] || STRENGTH_TEMPLATES[3]).dup
    other_days    = other_types.map { |t| { name: ACTIVITY_NAMES.fetch(t, t.capitalize), exercise_type: t } }

    (strength_days + other_days).first(@days_per_week)
  end
end
