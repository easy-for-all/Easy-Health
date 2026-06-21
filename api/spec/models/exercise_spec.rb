require "rails_helper"

RSpec.describe Exercise do
  it "accepts the curated safety tags used by strategy filters" do
    exercise = described_class.new(
      name: "Movimento seguro",
      exercise_type: "musculacao",
      safety_tags: %w[high_impact high_fall_risk]
    )

    expect(exercise).to be_valid
  end

  it "rejects unknown safety tags" do
    exercise = described_class.new(
      name: "Movimento desconhecido",
      exercise_type: "musculacao",
      safety_tags: [ "not_a_safety_tag" ]
    )

    expect(exercise).to be_invalid
    expect(exercise.errors[:safety_tags]).to be_present
  end
end
