require "rails_helper"

RSpec.describe Exercise do
  describe ".browseable" do
    it "returns only exercises from the gifdotreino GIF catalog" do
      valid = described_class.create!(
        name: "Supino Reto",
        exercise_type: "musculacao",
        muscle_group: "chest",
        gif_url: "/exercise-images/gifdotreino/peitoral/supino-reto.gif"
      )
      described_class.create!(
        name: "GIF legado",
        exercise_type: "musculacao",
        muscle_group: "chest",
        gif_url: "/exercise-images/supino-reto.gif"
      )
      described_class.create!(
        name: "JPG legado",
        exercise_type: "musculacao",
        muscle_group: "chest",
        image_url: "/exercise-images/db/Pushups/0.jpg"
      )
      described_class.create!(
        name: "Sem GIF",
        exercise_type: "cardio",
        equipment_type: "cardio"
      )

      expect(described_class.browseable).to contain_exactly(valid)
    end
  end

  describe ".gifdotreino_url?" do
    it "accepts only gifdotreino GIF URLs" do
      expect(described_class.gifdotreino_url?("/exercise-images/gifdotreino/peitoral/supino.gif")).to be(true)
      expect(described_class.gifdotreino_url?("/exercise-images/gifdotreino/peitoral/supino.jpg")).to be(false)
      expect(described_class.gifdotreino_url?("/exercise-images/supino.gif")).to be(false)
    end
  end

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
