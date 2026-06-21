require "rails_helper"

RSpec.describe AiWorkout::PromptBuilder do
  let(:user)            { create(:user) }
  let(:fitness_profile) { create(:fitness_profile, user: user, primary_persona: "hypertrophy_beginner", training_archetype: "aesthetic_hypertrophy", behavior_pattern: "consistent_short_sessions") }
  let(:prompt_version)  { create(:ai_prompt_version, name: "workout_generation", version: "v1", active: true, content: "Persona: {{persona}}\nArchetype: {{archetype}}\nBehavior: {{behavior}}\nScores: {{scores}}\nLimitations: {{limitations}}\nEquipment: {{equipment}}\nPreferred: {{preferred_exercises}}\nAvoided: {{avoided_exercises}}\nHistory: {{recent_history}}\nAvailable: {{available_exercises}}\nStrategy: {{strategy}}\nLevel: {{fitness_level}}\nGoal: {{goal}}\nDays: {{days_per_week}}") }

  before { prompt_version }

  subject(:builder) do
    described_class.new(
      user: user,
      fitness_profile: fitness_profile,
      days_per_week: 3
    )
  end

  describe "#call" do
    it "returns a prompt and prompt_version_id" do
      result = builder.call
      expect(result[:prompt]).to be_present
      expect(result[:prompt_version_id]).to eq(prompt_version.id)
    end

    it "includes persona in the prompt" do
      result = builder.call
      expect(result[:prompt]).to include("hypertrophy beginner")
    end

    it "includes archetype in the prompt" do
      result = builder.call
      expect(result[:prompt]).to include("aesthetic hypertrophy")
    end

    it "includes behavior in the prompt" do
      result = builder.call
      expect(result[:prompt]).to include("consistent short sessions")
    end

    it "does not include user email in the prompt" do
      result = builder.call
      expect(result[:prompt]).not_to include(user.email)
    end

    it "does not include user name in the prompt" do
      result = builder.call
      expect(result[:prompt]).not_to include(user.name)
    end

    context "when no active prompt version exists" do
      before { AiPromptVersion.update_all(active: false) }

      it "returns a fallback with nil prompt" do
        result = builder.call
        expect(result[:prompt]).to be_nil
        expect(result[:prompt_version_id]).to be_nil
      end
    end
  end
end
