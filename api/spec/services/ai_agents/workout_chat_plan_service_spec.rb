require "rails_helper"

RSpec.describe AiAgents::WorkoutChatPlanService do
  let(:user) { create(:user) }
  let(:collected_profile) do
    { "goal" => "gain_muscle", "fitness_level" => "intermediate", "training_days_per_week" => 2, "training_location" => "full_gym" }
  end

  let(:valid_plan_json) do
    {
      training_method: "upper_lower",
      plan_name: "Plano Teste",
      rationale: "Motivo qualquer.",
      week_structure: [
        { name: "Superior", muscle_groups: %w[chest back shoulders] },
        { name: "Inferior", muscle_groups: %w[legs core] }
      ],
      sets: 3, reps: 10, rest_seconds: 90,
      progression_strategy: "Progressão linear.",
      safety_notes: ["Aquecer antes de treinar"]
    }.to_json
  end

  subject(:service) { described_class.new(user, collected_profile: collected_profile) }

  describe "#call" do
    it "returns a valid, non-fallback plan when Claude returns valid JSON" do
      allow_any_instance_of(described_class).to receive(:call_claude).and_return(valid_plan_json)

      result = service.call

      expect(result[:valid]).to be true
      expect(result[:fallback]).to be false
      expect(result[:data][:training_method]).to eq("upper_lower")
      expect(result[:data][:week_structure].size).to eq(2)
    end

    it "retries once on invalid JSON and succeeds on the second attempt" do
      call_count = 0
      allow_any_instance_of(described_class).to receive(:call_claude) do
        call_count += 1
        call_count == 1 ? "not json" : valid_plan_json
      end

      result = service.call

      expect(call_count).to eq(2)
      expect(result[:valid]).to be true
      expect(result[:fallback]).to be false
    end

    it "falls back to a locally generated plan when both attempts return invalid JSON" do
      allow_any_instance_of(described_class).to receive(:call_claude).and_return("not json at all")

      result = service.call

      expect(result[:valid]).to be true
      expect(result[:fallback]).to be true
      expect(result[:data][:week_structure]).not_to be_empty
    end

    it "falls back when the safety validator reports a violation" do
      allow_any_instance_of(described_class).to receive(:call_claude).and_return(valid_plan_json)
      allow_any_instance_of(AiWorkout::SafetyValidator).to receive(:call)
        .and_return(valid: false, violations: ["volume excessivo"], warnings: [])

      result = service.call

      expect(result[:fallback]).to be true
    end

    context "when adjusting an existing preview" do
      subject(:service) do
        described_class.new(
          user, collected_profile: collected_profile,
          previous_preview: JSON.parse(valid_plan_json), adjust_instruction: "menos volume, por favor"
        )
      end

      it "includes the adjustment instruction and previous preview in the prompt" do
        captured_prompt = nil
        allow_any_instance_of(described_class).to receive(:call_claude) do |_, prompt, _task|
          captured_prompt = prompt
          valid_plan_json
        end

        service.call

        expect(captured_prompt).to include("menos volume, por favor")
        expect(captured_prompt).to include("PRÉVIA ANTERIOR")
      end
    end
  end
end
