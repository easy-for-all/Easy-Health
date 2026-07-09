module WorkoutIntelligence
  # Decides whether to group some of a day's already-selected exercises into
  # a composite block (superset/circuit). Purely deterministic - no LLM call
  # involved - so it runs identically regardless of how the day's exercises
  # were chosen (rule-based template, strategy, AI-driven week_structure, or
  # chat-confirmed plan): they all converge on
  # WorkoutPlanGeneratorService#call, which is the only caller of this class.
  #
  # Exercises stay ungrouped (single blocks, via WorkoutDayExercise's own
  # ensure_single_block! callback) unless this planner explicitly groups them.
  class BlockPlanner
    Result = Struct.new(:groups, :leftovers, keyword_init: true)
    GroupPlan = Struct.new(:block_type, :rounds, :rest_between_rounds_seconds, :rationale, :members, keyword_init: true)

    SHORT_SESSION_EXERCISE_LIMIT = 5

    def initialize(picks:, fitness_level:, goal:, day_exercise_limit:)
      @picks = picks
      @fitness_level = fitness_level.to_s.presence_in(%w[beginner intermediate advanced]) || "beginner"
      @goal_bucket = GoalTrainingProfile.normalize_goal(goal)
      @day_exercise_limit = day_exercise_limit.to_i
    end

    def call
      return empty_result if @picks.size < 2

      pool = @picks.select { |pick| eligible_for_grouping?(pick[:exercise]) }
      return empty_result if pool.size < 2

      return empty_result if max_group_size < 2

      groups = []
      while pool.size >= 2 && groups.size < max_groups
        size = @fitness_level == "beginner" ? 2 : [ max_group_size, pool.size ].min
        members = pool.shift(size)
        groups << build_group(members)
      end

      used_ids = groups.flat_map(&:members).map { |m| m[:exercise].id }
      Result.new(groups: groups, leftovers: @picks.reject { |p| used_ids.include?(p[:exercise].id) })
    end

    private

    def empty_result
      Result.new(groups: [], leftovers: @picks)
    end

    # Main/compound lifts never join a block under a strength goal (they stay
    # single, at full isolated focus). Non-advanced levels also exclude any
    # exercise the technical-level policy classifies as high complexity/risk,
    # regardless of goal - a block is never the place to introduce a harder
    # exercise than the user would otherwise get.
    def eligible_for_grouping?(exercise)
      return false if @goal_bucket == "strength" && ExerciseRoleClassifier.role_for(exercise) == :compound
      return true if @fitness_level == "advanced"

      classification = TechnicalLevelPolicy.classification_for(exercise)
      classification[:technical_complexity] != "high" && classification[:risk_level] != "high"
    end

    # beginner: superset only, never circuit ("iniciante não recebe bloco
    # complexo"). advanced: up to a 4-exercise circuit. intermediate: superset
    # only, except a conditioning goal explicitly favors circuits ("condicionamento:
    # circuitos fazem sentido") even before advanced level.
    def max_group_size
      return 2 if @fitness_level == "beginner"
      return 4 if @fitness_level == "advanced"

      @goal_bucket == "conditioning" ? 4 : 2
    end

    # beginner: at most one composite block per day, kept deliberately rare
    # ("poucos compostos, simples e seguros"). Everyone else: a short session
    # (few exercises fit) groups more aggressively to save time; a long
    # session stays mostly traditional.
    def max_groups
      return 1 if @fitness_level == "beginner"

      short_session? ? 2 : 1
    end

    def short_session?
      @day_exercise_limit.positive? && @day_exercise_limit <= SHORT_SESSION_EXERCISE_LIMIT
    end

    def build_group(members)
      block_type = block_type_for(members.size)
      GroupPlan.new(
        block_type: block_type,
        rounds: members.map { |m| m[:sets].to_i }.max.to_i.clamp(1, 5),
        rest_between_rounds_seconds: members.filter_map { |m| m[:rest_seconds].to_i.nonzero? }.max || 90,
        rationale: rationale_for(members, block_type),
        members: members
      )
    end

    def block_type_for(size)
      return "circuit" if size >= 3
      return "circuit" if @goal_bucket == "conditioning" && @fitness_level != "beginner"

      "superset"
    end

    def rationale_for(members, block_type)
      names = members.map { |m| m[:exercise].name }.join(" + ")

      if block_type == "circuit"
        "Circuito de #{members.size} exercícios para otimizar condicionamento e tempo de sessão: #{names}."
      else
        case @goal_bucket
        when "strength"
          "Superset acessório, sem comprometer os exercícios principais: #{names}."
        when "hypertrophy"
          "Superset para intensificar o estímulo de hipertrofia: #{names}."
        else
          "Superset para otimizar o tempo da sessão: #{names}."
        end
      end
    end
  end
end
