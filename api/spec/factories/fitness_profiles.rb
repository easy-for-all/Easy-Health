FactoryBot.define do
  factory :fitness_profile do
    association :user
    primary_persona          { "general_health" }
    secondary_persona        { nil }
    training_archetype       { "balanced_full_body" }
    secondary_training_archetype { nil }
    behavior_pattern         { "unknown" }
    fitness_level            { "beginner" }
    current_goal             { "health" }
    current_phase            { "adaptation" }
    training_maturity        { 0.0 }
    consistency_score        { 5.0 }
    adherence_score          { 5.0 }
    recovery_score           { 5.0 }
    mobility_score           { 5.0 }
    motivation_score         { 5.0 }
    risk_score               { 3.0 }
    preference_confidence_score { 3.0 }
    behavior_confidence_score   { 3.0 }
    preferred_body_focus     { [] }
    preferred_exercises      { [] }
    avoided_exercises        { [] }
    preferred_training_styles { [] }
    available_equipment      { [] }
    physical_limitations     { [] }
    metadata                 { {} }
    last_recalculated_at     { Time.current }
  end
end
