require "rails_helper"

RSpec.describe AiAgents::WorkoutChatMessageService do
  let(:user) { create(:user) }
  let(:conversation) do
    AiWorkoutChatConversation.new(
      user: user,
      status: "collecting",
      collected_profile: {},
      messages: []
    )
  end

  def service(message: "quero treinar 4x por semana", classification: :allowed_fitness_training)
    described_class.new(user, conversation: conversation, message: message, classification: classification)
  end

  describe "#call" do
    it "returns the parsed reply, extracted_profile and ready_for_plan on a valid response" do
      valid_json = {
        reply: "Legal! Só falta saber onde você treina.",
        extracted_profile: { goal: "gain_muscle", fitness_level: "intermediate", training_days_per_week: 4 },
        ready_for_plan: false
      }.to_json

      allow_any_instance_of(described_class).to receive(:call_claude).and_return(valid_json)

      result = service.call

      expect(result[:reply]).to include("onde você treina")
      expect(result[:extracted_profile]).to include("goal" => "gain_muscle")
      expect(result[:ready_for_plan]).to be false
    end

    it "retries once when the first response is invalid JSON, then succeeds" do
      valid_json = { reply: "ok", extracted_profile: {}, ready_for_plan: true }.to_json

      call_count = 0
      allow_any_instance_of(described_class).to receive(:call_claude) do
        call_count += 1
        call_count == 1 ? "not json" : valid_json
      end

      result = service.call

      expect(call_count).to eq(2)
      expect(result[:ready_for_plan]).to be true
    end

    it "falls back to a deterministic Ruby reply without a third Claude call when both attempts fail" do
      call_count = 0
      allow_any_instance_of(described_class).to receive(:call_claude) do
        call_count += 1
        "still not json"
      end

      result = service.call

      expect(call_count).to eq(2)
      expect(result[:ready_for_plan]).to be false
      expect(result[:extracted_profile]).to eq({})
      expect(result[:reply]).to be_present
    end

    it "asks about the first missing required field in the fallback" do
      conversation.collected_profile = { "goal" => "gain_muscle" }
      allow_any_instance_of(described_class).to receive(:call_claude).and_return(nil)

      result = service.call

      expect(result[:reply]).to include("nível")
    end

    it "includes a medical disclaimer instruction in the prompt when classification is medical_risk_needs_disclaimer" do
      captured_prompt = nil
      allow_any_instance_of(described_class).to receive(:call_claude) do |_, prompt, _task|
        captured_prompt = prompt
        { reply: "ok", extracted_profile: {}, ready_for_plan: false }.to_json
      end

      service(message: "sinto dor no joelho", classification: :medical_risk_needs_disclaimer).call

      expect(captured_prompt).to include("não substitui")
    end
  end
end
