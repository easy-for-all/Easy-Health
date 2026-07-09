module WorkoutIntelligence
  # Decides whether an exercise should be treated as a "compound" (main lift,
  # low reps/high rest under a strength goal) or "accessory" exercise.
  class ExerciseRoleClassifier
    COMPOUND_PATTERNS  = %w[squat hinge push pull lunge carry].freeze
    ACCESSORY_PATTERNS = %w[isolation rotation locomotion].freeze
    COMPOUND_PRONE_GROUPS = %w[chest back legs glutes shoulders].freeze
    COMPOUND_PRONE_EQUIPMENT = %w[barbell machine gym cable].freeze

    def self.role_for(exercise)
      return exercise.compound ? :compound : :accessory unless exercise.compound.nil?

      pattern = exercise.movement_pattern
      return :compound  if COMPOUND_PATTERNS.include?(pattern)
      return :accessory if ACCESSORY_PATTERNS.include?(pattern)

      if COMPOUND_PRONE_GROUPS.include?(exercise.muscle_group) && COMPOUND_PRONE_EQUIPMENT.include?(exercise.equipment_type)
        :compound
      else
        :accessory
      end
    end
  end
end
