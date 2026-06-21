require "rails_helper"

RSpec.describe CoachEngine::TrainingArchetypeClassifier do
  it "requires sufficient dominant execution signals before assigning a body focus" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, goal: "gain_muscle")
    fitness_profile = FitnessProfile.create!(user: user)
    glute_exercise = Exercise.create!(name: "Hip Thrust", exercise_type: "musculacao", muscle_group: "glutes")

    3.times do |index|
      user.workout_sessions.create!(
        completed_at: (index + 1).days.ago,
        duration_minutes: 35,
        exercise_logs: [ { "exercise_id" => glute_exercise.id } ]
      )
    end

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["training_archetype"]).to eq("glute_focused")
    expect(result["secondary_training_archetype"]).to eq("lower_body_focused")
  end

  it "uses a declared cardio-only preference before inferred body focus" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, activity_preferences: [ "corrida" ], goal: "gain_muscle")
    fitness_profile = FitnessProfile.create!(user: user)

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["training_archetype"]).to eq("cardio_focused")
  end

  it "keeps the archetype goal-based when declared focus lacks corroborating signals" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, goal: "strength", preferred_body_focus: [ "glutes" ])
    fitness_profile = FitnessProfile.create!(user: user)

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["training_archetype"]).to eq("strength_focused")
  end
end
