require "rails_helper"

RSpec.describe Ai::WorkoutChatReadiness do
  describe ".ready?" do
    it "is true when all minimum fields are present" do
      profile = {
        "goal" => "gain_muscle", "fitness_level" => "intermediate",
        "training_days_per_week" => 4, "training_location" => "home"
      }
      expect(described_class.ready?(profile)).to be true
    end

    it "is false when a required field is missing" do
      profile = { "goal" => "gain_muscle", "fitness_level" => "intermediate" }
      expect(described_class.ready?(profile)).to be false
    end

    it "is false for a blank profile" do
      expect(described_class.ready?({})).to be false
      expect(described_class.ready?(nil)).to be false
    end
  end
end
