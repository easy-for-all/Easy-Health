require "rails_helper"

RSpec.describe WorkoutIntelligence::GoalTrainingProfile do
  describe ".normalize_goal" do
    it "maps declared goals to the expected bucket" do
      expect(described_class.normalize_goal("strength")).to eq("strength")
      expect(described_class.normalize_goal("gain_muscle")).to eq("hypertrophy")
      expect(described_class.normalize_goal("lose_weight")).to eq("conditioning")
      expect(described_class.normalize_goal("mobility")).to eq("mobility")
      expect(described_class.normalize_goal(nil)).to eq("health")
      expect(described_class.normalize_goal("unknown_goal")).to eq("health")
    end
  end

  describe ".for" do
    it "gives strength a low-rep/high-rest compound prescription, clearly different from hypertrophy" do
      strength = described_class.for(goal: "strength", fitness_level: "intermediate", role: :compound)
      hypertrophy = described_class.for(goal: "gain_muscle", fitness_level: "intermediate", role: :compound)

      expect(strength[:reps]).to be < hypertrophy[:reps]
      expect(strength[:rest_seconds]).to be > hypertrophy[:rest_seconds]
    end

    it "never lands on reps:10/rest:75 for every role under a strength goal (the audited bug)" do
      compound = described_class.for(goal: "strength", fitness_level: "intermediate", role: :compound)
      accessory = described_class.for(goal: "strength", fitness_level: "intermediate", role: :accessory)
      audited_bug_values = { reps: 10, rest_seconds: 75 }

      expect([ compound, accessory ]).not_to include(a_hash_including(audited_bug_values))
    end

    it "matches the legacy SETS_REPS table for an unset/generic goal so existing behavior is preserved" do
      params = described_class.for(goal: nil, fitness_level: "intermediate", role: :accessory)

      expect(params).to eq(WorkoutPlanGeneratorService::SETS_REPS["intermediate"])
    end

    it "falls back to a safe default for an unknown fitness_level" do
      params = described_class.for(goal: "strength", fitness_level: "unknown", role: :compound)

      expect(params).to eq(described_class::PARAMS["strength"][:compound]["beginner"])
    end
  end
end
