module WorkoutIntelligence
  # Final gate before a generated plan is trusted, run for ALL generation
  # modes (rule-based, strategy, AI) — not just AI output like
  # AiWorkout::SafetyValidator. Re-checks the actually-persisted
  # WorkoutDayExercise rows against the technical level policy, weekly
  # volume targets, session limits, duplication and known limitations, and
  # auto-fixes what it safely can by substituting exercises via the same
  # ExerciseCandidateScope the generator used (so it never invents a
  # candidate outside what was already considered safe/available).
  class PlanValidator
    Result = Struct.new(:valid, :violations, :warnings, :auto_fixes, keyword_init: true)

    MAX_SETS_PER_EXERCISE = AiWorkout::SafetyValidator::MAX_SETS_PER_EXERCISE
    MAX_EXERCISES_PER_DAY = AiWorkout::SafetyValidator::MAX_EXERCISES_PER_DAY
    LIMITATION_TAG_MAP     = AiWorkout::SafetyValidator::LIMITATION_TAG_MAP
    VOLUME_WARNING_RATIO   = 0.5

    def initialize(plan:, health_profile:, fitness_level:, goal:, weekly_volume_targets:, candidate_scope:, decision_source:)
      @plan = plan
      @health_profile = health_profile
      @fitness_level = fitness_level
      @goal = goal
      @weekly_volume_targets = weekly_volume_targets || {}
      @candidate_scope = candidate_scope
      @decision_source = decision_source
      @violations = []
      @warnings = []
      @auto_fixes = []
    end

    def call
      check_structure!
      return build_result if @violations.any? { |v| v[:fatal] }

      check_forbidden_exercises!
      check_limitations!
      check_duplicates_within_day!
      check_session_volume!
      check_weekly_volume!

      build_result
    end

    private

    def build_result
      Result.new(valid: @violations.none? { |v| v[:fatal] }, violations: @violations, warnings: @warnings, auto_fixes: @auto_fixes)
    end

    def check_structure!
      if @plan.workout_days.empty?
        @violations << { code: :empty_plan, fatal: true, message: "Workout plan was not generated" }
        return
      end

      total_exercises = @plan.workout_days.sum { |d| d.workout_day_exercises.count }
      return unless total_exercises.zero?

      @violations << {
        code: :no_exercises_assigned, fatal: true,
        message: "No exercises could be assigned to this plan (level: #{@fitness_level}). Check exercise availability and user profile filters."
      }
    end

    def check_forbidden_exercises!
      each_exercise do |wde|
        next if TechnicalLevelPolicy.allowed?(wde.exercise, fitness_level: @fitness_level)

        reason = TechnicalLevelPolicy.blocked_reason(wde.exercise, fitness_level: @fitness_level)
        replace_exercise!(wde, reason: "technical_level:#{reason}")
      end
    end

    def check_limitations!
      limitations = Array(@health_profile&.limitations).map { |l| l.to_s.downcase }
      return if limitations.empty?

      forbidden_tags = LIMITATION_TAG_MAP.select { |_, affected| affected.any? { |a| limitations.any? { |l| l.include?(a) } } }.keys
      return if forbidden_tags.empty?

      each_exercise do |wde|
        next if (Array(wde.exercise.safety_tags) & forbidden_tags).empty?

        replace_exercise!(wde, reason: "limitation:#{(Array(wde.exercise.safety_tags) & forbidden_tags).join(',')}")
      end
    end

    def check_duplicates_within_day!
      @plan.workout_days.each do |day|
        seen = Set.new
        day.workout_day_exercises.order(:order_index).each do |wde|
          if seen.include?(wde.exercise_id)
            replace_exercise!(wde, reason: "duplicate_in_day", day_scope: day)
          else
            seen << wde.exercise_id
          end
        end
      end
    end

    def check_session_volume!
      @plan.workout_days.each do |day|
        exercises = day.workout_day_exercises.order(:order_index).to_a
        if exercises.size > MAX_EXERCISES_PER_DAY
          exercises.last(exercises.size - MAX_EXERCISES_PER_DAY).each do |wde|
            @auto_fixes << { code: :trimmed_excess_exercise, exercise: wde.exercise.name, day: day.name }
            wde.destroy
          end
        end

        day.workout_day_exercises.where("sets > ?", MAX_SETS_PER_EXERCISE).each do |wde|
          wde.update_column(:sets, MAX_SETS_PER_EXERCISE)
          @auto_fixes << { code: :capped_sets, exercise: wde.exercise.name, day: day.name }
        end
      end
    end

    def check_weekly_volume!
      actual = Hash.new(0.0)
      each_exercise { |wde| actual[wde.exercise.muscle_group] += wde.sets.to_i }

      @weekly_volume_targets.each do |group, target|
        next if target.to_f.zero?

        ratio = actual[group] / target.to_f
        next if ratio >= VOLUME_WARNING_RATIO

        @warnings << {
          code: :undertrained_group, group: group,
          message: "Grupo '#{group}' recebeu #{actual[group].round(1)} séries/semana, abaixo do alvo de #{target.round(1)} (#{(ratio * 100).round}%)"
        }
      end
    end

    def replace_exercise!(wde, reason:, day_scope: nil)
      day = day_scope || wde.workout_day
      used_ids_in_day = day.workout_day_exercises.where.not(id: wde.id).pluck(:exercise_id)

      substitute = TechnicalLevelPolicy.regression_for(wde.exercise, scope: @candidate_scope.base_relation)
      substitute = nil if substitute && (used_ids_in_day.include?(substitute.id) || !TechnicalLevelPolicy.allowed?(substitute, fitness_level: @fitness_level))

      substitute ||= @candidate_scope.candidates_for(wde.exercise)
        .where.not(id: used_ids_in_day)
        .find { |candidate| TechnicalLevelPolicy.allowed?(candidate, fitness_level: @fitness_level) }

      if substitute
        @auto_fixes << { code: :substituted_exercise, from: wde.exercise.name, to: substitute.name, reason: reason, day: day.name }
        wde.update!(exercise: substitute)
      else
        @auto_fixes << { code: :removed_unresolved_exercise, exercise: wde.exercise.name, reason: reason, day: day.name }
        wde.destroy
      end
    end

    def each_exercise
      @plan.workout_days.each do |day|
        day.workout_day_exercises.reload.each { |wde| yield wde }
      end
    end
  end
end
