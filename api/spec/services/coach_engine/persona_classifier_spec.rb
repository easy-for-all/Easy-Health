require "rails_helper"

RSpec.describe CoachEngine::PersonaClassifier do
  def classify(gender)
    user = create(:user)
    health_profile = create(
      :health_profile,
      user: user,
      gender: gender,
      fitness_level: "beginner",
      goal: "gain_muscle"
    )
    fitness_profile = FitnessProfile.create!(user: user)

    described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call
  end

  it "classifies hypertrophy from goal and level without using gender" do
    male = classify("male")
    female = classify("female")

    expect(male.slice("primary_persona", "secondary_persona")).to eq(female.slice("primary_persona", "secondary_persona"))
    expect(male["primary_persona"]).to eq("hypertrophy_beginner")
  end

  it "prioritizes the older-adult safety persona" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, age: 65, goal: "gain_muscle")
    fitness_profile = FitnessProfile.create!(user: user)

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["primary_persona"]).to eq("older_adult_mobility")
  end
end
