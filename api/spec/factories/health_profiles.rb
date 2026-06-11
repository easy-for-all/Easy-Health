FactoryBot.define do
  factory :health_profile do
    association :user
    age { 28 }
    weight_kg { 75.0 }
    height_cm { 175.0 }
    fitness_level { "intermediate" }
    goal { "gain_muscle" }
    training_days_per_week { 3 }
    activity_preferences { ["musculacao"] }
  end
end
