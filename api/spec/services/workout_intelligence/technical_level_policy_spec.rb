require "rails_helper"

RSpec.describe WorkoutIntelligence::TechnicalLevelPolicy do
  def exercise(name: "Test Exercise", **attrs)
    Exercise.create!(
      name: name, exercise_type: "musculacao", muscle_group: "back", equipment_type: "bodyweight",
      gif_url: "/exercise-images/gifdotreino/test/#{name.parameterize}.gif", **attrs
    )
  end

  describe ".allowed?" do
    it "blocks a high technical_complexity exercise for beginner but allows it for advanced" do
      ex = exercise(technical_complexity: "high", risk_level: "high", calisthenics_skill: "none")

      expect(described_class.allowed?(ex, fitness_level: "beginner")).to be(false)
      expect(described_class.allowed?(ex, fitness_level: "advanced")).to be(true)
    end

    it "blocks advanced calisthenics_skill for beginner and intermediate, allows for advanced" do
      ex = exercise(name: "Muscle Up", calisthenics_skill: "advanced", technical_complexity: "high", risk_level: "high")

      expect(described_class.allowed?(ex, fitness_level: "beginner")).to be(false)
      expect(described_class.allowed?(ex, fitness_level: "intermediate")).to be(false)
      expect(described_class.allowed?(ex, fitness_level: "advanced")).to be(true)
    end

    it "allows a basic-skill exercise for intermediate but not for beginner" do
      ex = exercise(name: "Barra Fixa", calisthenics_skill: "basic", technical_complexity: "medium", risk_level: "medium")

      expect(described_class.allowed?(ex, fitness_level: "beginner")).to be(false)
      expect(described_class.allowed?(ex, fitness_level: "intermediate")).to be(true)
    end

    it "allows a high-complexity barbell lift for intermediate (not just advanced)" do
      ex = exercise(name: "Levantamento Terra", technical_complexity: "high", risk_level: "high", calisthenics_skill: "none")

      expect(described_class.allowed?(ex, fitness_level: "intermediate")).to be(true)
    end

    it "falls back to name-pattern matching when no explicit column is set" do
      ex = exercise(name: "Handstand Push-up")

      expect(described_class.allowed?(ex, fitness_level: "beginner")).to be(false)
      expect(described_class.allowed?(ex, fitness_level: "advanced")).to be(true)
    end

    it "does not let a legacy safety_tags advanced_skill tag override an explicit safe classification" do
      ex = exercise(name: "Barra Fixa Assistida", calisthenics_skill: "none", technical_complexity: "low",
        risk_level: "low", safety_tags: [ "advanced_skill" ])

      expect(described_class.allowed?(ex, fitness_level: "beginner")).to be(true)
    end

    it "allows an exercise with no metadata and no matching name pattern for any level" do
      ex = exercise(name: "Rosca Martelo")

      expect(described_class.allowed?(ex, fitness_level: "beginner")).to be(true)
    end
  end

  describe ".regression_for" do
    it "prefers the explicit regression_exercise column over the curated RegressionMap" do
      target = exercise(name: "Assistida Explícita")
      ex = exercise(name: "Muscle Up", regression_exercise: target)

      expect(described_class.regression_for(ex, scope: Exercise.all)).to eq(target)
    end
  end
end
