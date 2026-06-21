require "rails_helper"

RSpec.describe CoachEngine::ProfileAnalyzer do
  it "persists agent outputs, preserves the higher risk score, and only emits classification events on change" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, goal: "gain_muscle", fitness_level: "beginner")
    fitness_profile = FitnessProfile.create!(user: user, risk_score: 5)

    described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call(source: "spec")

    fitness_profile.reload
    expect(fitness_profile.classification_version).to eq("v2")
    expect(fitness_profile.primary_persona).to eq("hypertrophy_beginner")
    expect(fitness_profile.metadata.dig("coach_engine", "persona", "explanation")).to be_present
    expect(fitness_profile.risk_score).to be >= 5
    expect(user.user_events.where(event_name: "persona_classified").count).to eq(1)

    described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call(source: "spec")

    expect(user.user_events.where(event_name: "persona_classified").count).to eq(1)
  end
end
