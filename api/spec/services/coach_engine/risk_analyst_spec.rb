require "rails_helper"

RSpec.describe CoachEngine::RiskAnalyst do
  it "returns conservative lower-body constraints for a declared knee limitation" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, limitations: [ "joelho" ], fitness_level: "beginner")
    fitness_profile = FitnessProfile.create!(user: user, risk_score: 4)

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["risk_score"]).to be > 4
    expect(result["forbidden_exercise_patterns"]).to include("deep_knee_flexion")
    expect(result["required_regressions"]).to include("supported_lower_body_variation")
  end

  it "adds conservative safeguards for a declared pregnancy context" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, training_context: "pregnant")
    fitness_profile = FitnessProfile.create!(user: user, risk_score: 4)

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["forbidden_exercise_patterns"]).to include("high_fall_risk")
    expect(result["required_regressions"]).to include("low_impact_variation")
    expect(result["caution_notes"].join).to include("gestacional")
  end
end
