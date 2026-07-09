module WorkoutIntelligence
  # Decides whether an exercise is technically/safely appropriate for a given
  # fitness level. An explicit column (technical_complexity, risk_level,
  # calisthenics_skill) always wins; when an exercise was never classified
  # (all three columns nil), a name-pattern fallback blocks the highest-skill
  # movements for beginner/intermediate users so the ~900 unenriched
  # exercises in the catalog don't silently bypass the safety gate.
  class TechnicalLevelPolicy
    COMPLEXITY_RANK    = { "low" => 0, "medium" => 1, "high" => 2 }.freeze
    CALISTHENICS_RANK  = { "none" => 0, "basic" => 1, "advanced" => 2 }.freeze

    MAX_TECHNICAL_COMPLEXITY = { "beginner" => "low",  "intermediate" => "high",  "advanced" => "high" }.freeze
    MAX_RISK_LEVEL           = { "beginner" => "medium", "intermediate" => "high", "advanced" => "high" }.freeze
    MAX_CALISTHENICS_SKILL   = { "beginner" => "none",  "intermediate" => "basic", "advanced" => "advanced" }.freeze

    # Movements that require dedicated skill practice regardless of general
    # strength/fitness level. Used only as a fallback for exercises without
    # explicit metadata (mirrors lib/tasks/exercises.rake::ADVANCED_PATTERNS,
    # extended). Restricted to `advanced` users when matched.
    NAME_FALLBACK_PATTERNS = [
      "muscle up", "muscle-up", "handstand", "pistol squat", "one-arm",
      "clean and jerk", "snatch", "power clean", "hang clean", "jerk",
      "front squat barbell", "overhead squat", "turkish get-up",
      "back lever", "front lever", "planche", "human flag"
    ].freeze

    def self.allowed?(exercise, fitness_level:)
      blocked_reason(exercise, fitness_level: fitness_level).nil?
    end

    def self.blocked_reason(exercise, fitness_level:)
      level = fitness_level.to_s.presence_in(%w[beginner intermediate advanced]) || "beginner"
      classification = classification_for(exercise)

      if classification[:technical_complexity] &&
         COMPLEXITY_RANK.fetch(classification[:technical_complexity], 0) > COMPLEXITY_RANK.fetch(MAX_TECHNICAL_COMPLEXITY[level], 2)
        return :technical_complexity
      end

      if classification[:risk_level] &&
         COMPLEXITY_RANK.fetch(classification[:risk_level], 0) > COMPLEXITY_RANK.fetch(MAX_RISK_LEVEL[level], 2)
        return :risk_level
      end

      if classification[:calisthenics_skill] &&
         CALISTHENICS_RANK.fetch(classification[:calisthenics_skill], 0) > CALISTHENICS_RANK.fetch(MAX_CALISTHENICS_SKILL[level], 2)
        return :calisthenics_skill
      end

      if classification[:source] == :name_fallback && level != "advanced"
        return :name_fallback
      end

      nil
    end

    # Returns the classification actually used to gate this exercise —
    # explicit columns when present, otherwise a name-pattern guess.
    def self.classification_for(exercise)
      if exercise.technical_complexity.present? || exercise.risk_level.present? || exercise.calisthenics_skill.present?
        return {
          technical_complexity: exercise.technical_complexity,
          risk_level: exercise.risk_level,
          calisthenics_skill: exercise.calisthenics_skill,
          source: :column
        }
      end

      name = exercise.name.to_s.downcase
      if NAME_FALLBACK_PATTERNS.any? { |pattern| name.include?(pattern) } ||
         Array(exercise.safety_tags).include?("advanced_skill")
        return { technical_complexity: nil, risk_level: nil, calisthenics_skill: nil, source: :name_fallback }
      end

      { technical_complexity: nil, risk_level: nil, calisthenics_skill: nil, source: :default }
    end

    # SQL fragment (safe: built only from our own constants) used by
    # Exercise.technically_safe_for. Blocks exercises whose EXPLICIT columns
    # exceed the level's allowance, and — for non-advanced levels — exercises
    # with no metadata at all whose name matches a skill-movement pattern.
    def self.sql_conditions_for(fitness_level)
      level = fitness_level.to_s.presence_in(%w[beginner intermediate advanced]) || "beginner"

      allowed_complexity   = ranks_up_to(COMPLEXITY_RANK, MAX_TECHNICAL_COMPLEXITY[level])
      allowed_risk         = ranks_up_to(COMPLEXITY_RANK, MAX_RISK_LEVEL[level])
      allowed_calisthenics = ranks_up_to(CALISTHENICS_RANK, MAX_CALISTHENICS_SKILL[level])

      conditions = [
        "(technical_complexity IS NULL OR technical_complexity IN (?))",
        "(risk_level IS NULL OR risk_level IN (?))",
        "(calisthenics_skill IS NULL OR calisthenics_skill IN (?))"
      ]
      values = [ allowed_complexity, allowed_risk, allowed_calisthenics ]

      if level != "advanced"
        name_pattern = NAME_FALLBACK_PATTERNS.map { |p| "%#{p}%" }
        unclassified = "(technical_complexity IS NULL AND risk_level IS NULL AND calisthenics_skill IS NULL)"
        fallback_signal = "((#{name_pattern.map { "name ILIKE ?" }.join(' OR ')}) OR safety_tags @> ARRAY['advanced_skill']::text[])"
        conditions << "NOT (#{unclassified} AND #{fallback_signal})"
        values.concat(name_pattern)
      end

      ActiveRecord::Base.sanitize_sql_array([ conditions.join(" AND "), *values ])
    end

    def self.regression_for(exercise, scope: Exercise.browseable)
      exercise.regression_exercise || RegressionMap.resolve(exercise.name, scope: scope)
    end

    def self.ranks_up_to(rank_map, max_key)
      max_rank = rank_map.fetch(max_key, rank_map.values.max)
      rank_map.select { |_, rank| rank <= max_rank }.keys
    end
    private_class_method :ranks_up_to
  end
end
