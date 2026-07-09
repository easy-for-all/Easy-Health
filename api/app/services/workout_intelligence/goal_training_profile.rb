module WorkoutIntelligence
  # Maps a declared HealthProfile#goal + fitness_level + exercise role
  # (compound vs accessory) to sets/reps/rest_seconds. This is the piece that
  # was completely missing before: the legacy WorkoutPlanGeneratorService::SETS_REPS
  # only keyed off fitness_level, so "ganhar força" and "ganhar massa" produced
  # identical prescriptions. The "health" bucket is calibrated to reproduce
  # those legacy values exactly, so generic/unset goals don't change behavior.
  class GoalTrainingProfile
    GOAL_BUCKETS = {
      "lose_weight"      => "conditioning",
      "gain_muscle"       => "hypertrophy",
      "maintain"          => "health",
      "health"            => "health",
      "body_definition"   => "hypertrophy",
      "conditioning"      => "conditioning",
      "strength"          => "strength",
      "mobility"          => "mobility",
      "safe_return"       => "health",
      "health_longevity"  => "health"
    }.freeze

    FITNESS_LEVELS = %w[beginner intermediate advanced].freeze

    # bucket => role => fitness_level => {sets:, reps:, rest_seconds:}
    PARAMS = {
      "strength" => {
        compound: {
          "beginner"     => { sets: 3, reps: 6,  rest_seconds: 120 },
          "intermediate" => { sets: 4, reps: 5,  rest_seconds: 150 },
          "advanced"     => { sets: 5, reps: 4,  rest_seconds: 180 }
        },
        accessory: {
          "beginner"     => { sets: 3, reps: 10, rest_seconds: 75 },
          "intermediate" => { sets: 3, reps: 8,  rest_seconds: 90 },
          "advanced"     => { sets: 3, reps: 6,  rest_seconds: 120 }
        }
      },
      "hypertrophy" => {
        compound: {
          "beginner"     => { sets: 3, reps: 10, rest_seconds: 75 },
          "intermediate" => { sets: 4, reps: 10, rest_seconds: 90 },
          "advanced"     => { sets: 4, reps: 8,  rest_seconds: 90 }
        },
        accessory: {
          "beginner"     => { sets: 3, reps: 12, rest_seconds: 60 },
          "intermediate" => { sets: 3, reps: 12, rest_seconds: 60 },
          "advanced"     => { sets: 4, reps: 15, rest_seconds: 45 }
        }
      },
      "conditioning" => {
        compound: {
          "beginner"     => { sets: 3, reps: 15, rest_seconds: 45 },
          "intermediate" => { sets: 3, reps: 15, rest_seconds: 40 },
          "advanced"     => { sets: 4, reps: 15, rest_seconds: 30 }
        },
        accessory: {
          "beginner"     => { sets: 3, reps: 15, rest_seconds: 40 },
          "intermediate" => { sets: 3, reps: 18, rest_seconds: 35 },
          "advanced"     => { sets: 3, reps: 20, rest_seconds: 30 }
        }
      },
      "mobility" => {
        compound: {
          "beginner"     => { sets: 2, reps: 12, rest_seconds: 30 },
          "intermediate" => { sets: 2, reps: 12, rest_seconds: 30 },
          "advanced"     => { sets: 3, reps: 12, rest_seconds: 30 }
        },
        accessory: {
          "beginner"     => { sets: 2, reps: 12, rest_seconds: 30 },
          "intermediate" => { sets: 2, reps: 12, rest_seconds: 30 },
          "advanced"     => { sets: 2, reps: 15, rest_seconds: 30 }
        }
      },
      "health" => {
        compound: {
          "beginner"     => { sets: 3, reps: 10, rest_seconds: 90 },
          "intermediate" => { sets: 4, reps: 10, rest_seconds: 75 },
          "advanced"     => { sets: 4, reps: 12, rest_seconds: 60 }
        },
        accessory: {
          "beginner"     => { sets: 3, reps: 10, rest_seconds: 90 },
          "intermediate" => { sets: 4, reps: 10, rest_seconds: 75 },
          "advanced"     => { sets: 4, reps: 12, rest_seconds: 60 }
        }
      }
    }.freeze

    def self.normalize_goal(raw_goal)
      GOAL_BUCKETS.fetch(raw_goal.to_s, "health")
    end

    def self.for(goal:, fitness_level:, role:)
      bucket = normalize_goal(goal)
      level  = FITNESS_LEVELS.include?(fitness_level.to_s) ? fitness_level.to_s : "beginner"
      role_key = role.to_sym == :compound ? :compound : :accessory

      PARAMS.dig(bucket, role_key, level) || PARAMS.dig("health", :accessory, "beginner")
    end
  end
end
