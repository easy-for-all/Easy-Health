require "rails_helper"

RSpec.describe AiWorkout::FallbackGenerator do
  let(:user) { create(:user) }

  before do
    create(:health_profile, user: user, fitness_level: "beginner", training_days_per_week: 3)
  end

  subject(:generator) { described_class.new(user: user, reason: "test_failure") }

  describe "#call" do
    it "returns a result with valid: true" do
      result = generator.call
      expect(result[:valid]).to be true
    end

    it "marks the result as a fallback" do
      result = generator.call
      expect(result[:fallback]).to be true
      expect(result[:fallback_reason]).to eq("test_failure")
    end

    it "returns a week_structure with at least one day" do
      result = generator.call
      expect(result[:data][:week_structure]).not_to be_empty
    end

    it "includes personalization_reason" do
      result = generator.call
      expect(result[:data][:personalization_reason]).to be_present
    end

    it "includes safety_notes" do
      result = generator.call
      expect(result[:data][:safety_notes]).not_to be_empty
    end

    it "does not call Claude or OpenAI" do
      expect_any_instance_of(AiAgents::WorkoutPlannerService).not_to receive(:call)
      generator.call
    end
  end
end
