module WorkoutIntelligence
  # Curated regression chains: canonical exercise name => safer alternatives,
  # ordered by preference. Used both to seed `regression_exercise_id` during
  # enrichment and as a runtime fallback in TechnicalLevelPolicy#regression_for
  # when the column isn't set (exercise wasn't part of the curated seed).
  CURATED = {
    "Muscle Up"           => [ "Barra Fixa Assistida", "Remada Invertida", "Puxada Alta Com Triangulo" ],
    "Barra Fixa"          => [ "Barra Fixa Assistida", "Puxada Alta Com Triangulo" ],
    "Levantamento Terra"  => [ "Levantamento Terra Romeno Com Halteres", "Mesa Flexora" ],
    "Agachamento Barra"   => [ "Leg Press", "Agachamento Goblet Com Haltere" ],
    "Agachamento Frontal" => [ "Leg Press", "Agachamento Goblet Com Haltere" ],
    "Triceps No Banco"    => [ "Triceps Pulley Corda" ],
    "Pistol Squat"        => [ "Agachamento Goblet Com Haltere", "Leg Press" ],
  }.freeze

  class RegressionMap
    def self.names_for(exercise_name)
      normalized = NameMatcher.normalize(exercise_name)
      key = CURATED.keys.find { |k| NameMatcher.normalize(k) == normalized }
      key ? CURATED.fetch(key) : []
    end

    # Returns the first browseable candidate (by name) that actually exists
    # in the given scope, trying each curated alternative in order.
    def self.resolve(exercise_name, scope: Exercise.browseable)
      names_for(exercise_name).each do |candidate_name|
        match = NameMatcher.best_match(candidate_name, scope.to_a)
        return match if match
      end
      nil
    end
  end
end
