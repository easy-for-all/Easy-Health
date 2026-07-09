module WorkoutIntelligence
  # Single place that builds the "safe, available, on-brand" exercise
  # relation for a user — location, technical/level safety, strategy
  # exclusions (avoided exercises, forbidden safety tags, equipment),
  # favorite/gif ordering. Moved out of WorkoutPlanGeneratorService#exercise_scope
  # so the exact same object can be reused by PlanValidator when it needs to
  # find a substitute for an exercise that shouldn't have been selected.
  class ExerciseCandidateScope
    OUTDOOR_COMPATIBLE_EQUIPMENT = %w[bodyweight cardio].freeze

    EQUIPMENT_TYPE_MAPPING = {
      "machine" => %w[machine gym],
      "dumbbell" => [ "dumbbell" ],
      "barbell" => [ "barbell" ],
      "plates" => [ "barbell" ],
      "resistance_band" => [ "bodyweight" ],
      "treadmill" => [ "cardio" ],
      "stationary_bike" => [ "cardio" ],
      "rower" => [ "cardio" ],
      "jump_rope" => [ "bodyweight" ]
    }.freeze

    def initialize(training_location:, fitness_level:, strategy: nil, available_equipment: [], fav_exercise_ids: [])
      @training_location = training_location
      @fitness_level = fitness_level
      @strategy = strategy
      @available_equipment = Array(available_equipment)
      @fav_exercise_ids = Array(fav_exercise_ids)
    end

    # Safety/location/level/strategy-filtered relation, no muscle_group or
    # exercise_type constraint — used directly by TopUpFiller to relax type.
    def base_relation
      rel = Exercise.browseable

      rel = case @training_location
            when "home"    then rel.where(home_compatible: true)
            when "outdoor" then rel.where(equipment_type: OUTDOOR_COMPATIBLE_EQUIPMENT)
            else rel
            end

      rel = rel.merge(Exercise.technically_safe_for(@fitness_level)) if @fitness_level.present?
      rel = strategy_filtered(rel) if @strategy

      rel.order(fav_priority_sql, gif_priority_sql, :id)
    end

    def for_group(group)
      base_relation.where(exercise_type: "musculacao", muscle_group: group)
    end

    def for_exercise_type(type)
      base_relation.where(exercise_type: type)
    end

    # Same muscle_group/exercise_type as the given exercise, used by
    # PlanValidator to find a substitute.
    def candidates_for(exercise)
      base_relation
        .where(muscle_group: exercise.muscle_group, exercise_type: exercise.exercise_type)
        .where.not(id: exercise.id)
    end

    private

    def strategy_filtered(relation)
      rel = relation.where.not(id: Array(@strategy["avoided_exercises"]))

      forbidden_tags = Array(@strategy["forbidden_exercises"])
      rel = rel.where.not("safety_tags && ARRAY[?]::text[]", forbidden_tags) if forbidden_tags.any?

      equipment_types = strategy_equipment_types
      rel = rel.where(equipment_type: equipment_types) if equipment_types.any?
      rel
    end

    def strategy_equipment_types
      return [] if @available_equipment.empty?
      return [ "bodyweight" ] if @available_equipment.include?("none") || @available_equipment.include?("bodyweight")

      @available_equipment.flat_map { |item| EQUIPMENT_TYPE_MAPPING.fetch(item, []) }.uniq.presence || [ "bodyweight" ]
    end

    def fav_priority_sql
      if @fav_exercise_ids.any?
        Arel.sql("CASE WHEN id IN (#{@fav_exercise_ids.map(&:to_i).join(',')}) THEN 0 ELSE 1 END")
      else
        Arel.sql("1")
      end
    end

    def gif_priority_sql
      Arel.sql("CASE WHEN gif_url IS NOT NULL THEN 0 ELSE 1 END")
    end
  end
end
