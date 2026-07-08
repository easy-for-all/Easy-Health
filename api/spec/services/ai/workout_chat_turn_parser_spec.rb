require "rails_helper"

RSpec.describe Ai::WorkoutChatTurnParser do
  describe "#call" do
    context "with valid JSON" do
      let(:raw) do
        {
          reply: "Legal! Só falta saber onde você treina.",
          extracted_profile: {
            goal: "gain_muscle",
            fitness_level: "intermediate",
            training_days_per_week: 4,
            available_equipment: ["dumbbell", "not_a_real_option"],
            session_duration_minutes: 42,
            junk_field: "should be dropped"
          },
          ready_for_plan: false
        }.to_json
      end

      subject(:result) { described_class.new(raw).call }

      it "returns valid: true" do
        expect(result[:valid]).to be true
      end

      it "extracts the reply" do
        expect(result[:data][:reply]).to include("onde você treina")
      end

      it "keeps only known, valid profile fields" do
        profile = result[:data][:extracted_profile]
        expect(profile).to include("goal" => "gain_muscle", "fitness_level" => "intermediate", "training_days_per_week" => 4)
        expect(profile).not_to have_key("junk_field")
      end

      it "drops invalid equipment options but keeps valid ones" do
        expect(result[:data][:extracted_profile]["available_equipment"]).to eq(["dumbbell"])
      end

      it "snaps session_duration_minutes to the nearest allowed value" do
        expect(result[:data][:extracted_profile]["session_duration_minutes"]).to eq(45)
      end

      it "defaults ready_for_plan to false when absent or falsy" do
        expect(result[:data][:ready_for_plan]).to be false
      end
    end

    context "when ready_for_plan is true" do
      let(:raw) { { reply: "Prontinho!", extracted_profile: {}, ready_for_plan: true }.to_json }

      it "returns ready_for_plan: true" do
        expect(described_class.new(raw).call[:data][:ready_for_plan]).to be true
      end
    end

    context "with an invalid goal value" do
      let(:raw) { { reply: "ok", extracted_profile: { goal: "become_a_wizard" }, ready_for_plan: false }.to_json }

      it "drops the invalid field instead of raising" do
        expect(described_class.new(raw).call[:data][:extracted_profile]).not_to have_key("goal")
      end
    end

    context "with a blank reply" do
      let(:raw) { { reply: "", extracted_profile: {}, ready_for_plan: false }.to_json }

      it "returns valid: false" do
        expect(described_class.new(raw).call[:valid]).to be false
      end
    end

    context "with nil response" do
      it "returns valid: false" do
        expect(described_class.new(nil).call[:valid]).to be false
      end
    end

    context "with invalid JSON" do
      it "returns valid: false" do
        expect(described_class.new("not json at all").call[:valid]).to be false
      end
    end
  end
end
