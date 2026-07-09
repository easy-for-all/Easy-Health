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
    MAX_CIRCUIT_SIZE_NON_ADVANCED = 4
    MIN_BLOCK_SIZE = { "superset" => 2, "bi_set" => 2, "tri_set" => 3, "circuit" => 3 }.freeze

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
      check_composite_block_safety!

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
            safely_destroy!(wde)
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
        safely_destroy!(wde)
      end
    end

    def each_exercise
      @plan.workout_days.each do |day|
        day.workout_day_exercises.reload.each { |wde| yield wde }
      end
    end

    # Bloqueia combinações de bloco perigosas (item 11): dois exercícios de
    # alta complexidade/risco juntos fora do nível advanced, circuito grande
    # demais para o nível, ou dois+ exercícios compostos num bloco quando o
    # objetivo é força. Auto-fix = dissolve o bloco inteiro em blocos single
    # (os exercícios continuam no plano, só deixam de ser feitos juntos).
    def check_composite_block_safety!
      @plan.workout_days.each do |day|
        day.workout_blocks.where(block_type: WorkoutBlock::MULTI_EXERCISE_TYPES).each do |block|
          exercises = block.workout_day_exercises.includes(:exercise).map(&:exercise)
          reason = composite_block_violation_reason(block.block_type, exercises)
          next unless reason

          dissolve_block!(block)
          @auto_fixes << { code: :dissolved_unsafe_block, block_type: block.block_type, reason: reason, day: day.name }
        end
      end
    end

    def composite_block_violation_reason(block_type, exercises)
      return "too_many_high_risk_exercises_together" if too_many_high_risk_together?(exercises)

      if block_type == "circuit" && @fitness_level != "advanced" && exercises.size > MAX_CIRCUIT_SIZE_NON_ADVANCED
        return "circuit_too_large_for_level"
      end

      if strength_goal? && exercises.count { |ex| WorkoutIntelligence::ExerciseRoleClassifier.role_for(ex) == :compound } >= 2
        return "multiple_compound_exercises_in_strength_block"
      end

      nil
    end

    def too_many_high_risk_together?(exercises)
      return false if @fitness_level == "advanced"

      exercises.count { |ex| high_risk_exercise?(ex) } >= 2
    end

    def high_risk_exercise?(exercise)
      classification = TechnicalLevelPolicy.classification_for(exercise)
      classification[:technical_complexity] == "high" || classification[:risk_level] == "high"
    end

    def strength_goal?
      WorkoutIntelligence::GoalTrainingProfile.normalize_goal(@goal) == "strength"
    end

    # Ungroups every exercise in a composite block into its own "single"
    # block. workout_block_id is NOT NULL, so each exercise is moved straight
    # to its new single block in one update - it must never pass through a
    # transient nil (unlike WorkoutDayExercise#ensure_single_block!, which
    # only runs before_create, when the row doesn't exist in the DB yet).
    def dissolve_block!(block)
      day = block.workout_day
      block.workout_day_exercises.each do |wde|
        next_position = day.workout_blocks.maximum(:position).to_i + 1
        single = day.workout_blocks.create!(block_type: "single", position: next_position, rounds: 1)
        wde.update_columns(workout_block_id: single.id, position_in_block: 0)
      end
      block.destroy
    end

    # Destroying one exercise of a multi-exercise block can leave the block
    # below its type's minimum size (e.g. a 3-exercise circuit trimmed to 2).
    # When that would happen, the whole block is dissolved into singles first
    # so no WorkoutBlock ever ends up structurally invalid.
    def safely_destroy!(wde)
      if wde.in_multi_exercise_block? && would_break_block?(wde)
        dissolve_block!(wde.workout_block)
        wde.reload
      end
      wde.destroy
    end

    def would_break_block?(wde)
      block = wde.workout_block
      min_size = MIN_BLOCK_SIZE.fetch(block.block_type, 2)
      block.workout_day_exercises.count - 1 < min_size
    end
  end
end
