module WorkoutIntelligence
  # Computes a weekly sets-per-muscle-group target BEFORE the generator
  # builds individual days, then translates that target into how many
  # exercises each day should carry for a given group. This is the piece
  # that replaces the flat EXERCISES_PER_GROUP=2 constant that caused
  # shallow leg days and ignored session duration entirely.
  class WeeklyVolumePlanner
    FITNESS_LEVELS = %w[beginner intermediate advanced].freeze

    # bucket => fitness_level => target weekly sets per muscle group
    BASE_SETS_PER_GROUP = {
      "strength"     => { "beginner" => 6, "intermediate" => 9,  "advanced" => 12 },
      "hypertrophy"  => { "beginner" => 8, "intermediate" => 12, "advanced" => 16 },
      "conditioning" => { "beginner" => 6, "intermediate" => 8,  "advanced" => 10 },
      "mobility"     => { "beginner" => 4, "intermediate" => 4,  "advanced" => 6 },
      "health"       => { "beginner" => 6, "intermediate" => 8,  "advanced" => 10 }
    }.freeze

    DURATION_MULTIPLIER = { 15 => 0.5, 25 => 0.7, 35 => 0.85, 45 => 1.0, 60 => 1.15 }.freeze
    FOCUS_BOOST = 1.3
    CORE_MINIMUM_WEEKLY_SETS = 4

    FOCUS_ALIASES = {
      "abs" => %w[core],
      "arms" => %w[biceps triceps],
      "mobility_posture" => %w[core],
      "full_body" => %w[chest back legs shoulders core]
    }.freeze

    def initialize(goal:, fitness_level:, days_per_week:, session_duration_minutes: nil,
                   preferred_body_focus: [], groups_in_template: [])
      @bucket = GoalTrainingProfile.normalize_goal(goal)
      @fitness_level = FITNESS_LEVELS.include?(fitness_level.to_s) ? fitness_level.to_s : "beginner"
      @days_per_week = days_per_week.to_i
      @session_duration_minutes = session_duration_minutes
      @preferred_body_focus = expand_focus(Array(preferred_body_focus))
      @groups_in_template = Array(groups_in_template).uniq
    end

    def call
      @targets = @groups_in_template.each_with_object({}) do |group, targets|
        base = BASE_SETS_PER_GROUP.dig(@bucket, @fitness_level) || BASE_SETS_PER_GROUP.dig("health", @fitness_level)
        base *= DURATION_MULTIPLIER.fetch(@session_duration_minutes, 1.0)
        base *= FOCUS_BOOST if @preferred_body_focus.include?(group)
        targets[group] = base.round(1)
      end

      enforce_legs_not_undertrained!
      enforce_core_minimum!

      @targets
    end

    def sets_per_day_occurrence(group:, occurrences_in_week:)
      target = @targets&.fetch(group, nil)
      return 0 unless target

      occurrences = [ occurrences_in_week.to_i, 1 ].max
      (target / occurrences.to_f).round
    end

    def exercise_count(group:, occurrences_in_week:, sets_per_exercise: 3)
      sets_today = sets_per_day_occurrence(group: group, occurrences_in_week: occurrences_in_week)
      return 1 if sets_today <= 0

      (sets_today / sets_per_exercise.to_f).ceil.clamp(1, 5)
    end

    private

    def expand_focus(raw_focus)
      raw_focus.flat_map { |focus| FOCUS_ALIASES.fetch(focus, [ focus ]) }.uniq
    end

    # Legs must never be trained less than chest in strength/hypertrophy
    # plans with enough frequency to support it — this is the direct fix
    # for the "5x/week leg day with only 2 exercises" bug.
    def enforce_legs_not_undertrained!
      return unless @targets.key?("legs") && @targets.key?("chest")
      return unless @days_per_week >= 4
      return unless %w[strength hypertrophy].include?(@bucket)

      @targets["legs"] = [ @targets["legs"], @targets["chest"] ].max
    end

    def enforce_core_minimum!
      return unless @targets.key?("core")

      @targets["core"] = [ @targets["core"], CORE_MINIMUM_WEEKLY_SETS ].max
    end
  end
end
