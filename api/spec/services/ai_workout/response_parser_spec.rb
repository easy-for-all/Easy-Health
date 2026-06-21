require "rails_helper"

RSpec.describe AiWorkout::ResponseParser do
  VALID_JSON = <<~JSON
    {
      "training_method": "upper_lower",
      "plan_name": "Plano Hipertrofia",
      "rationale": "Escolhemos upper_lower para hipertrofia.",
      "personalization_reason": "Montei este treino porque você quer hipertrofia.",
      "user_explanation": "Seu treino está pronto! Foco em superiores e inferiores.",
      "coach_notes": "Progrida 1 rep por semana.",
      "week_structure": [
        { "name": "Superior", "muscle_groups": ["chest", "back", "shoulders"] },
        { "name": "Inferior", "muscle_groups": ["legs", "core"] }
      ],
      "sets": 4,
      "reps": 10,
      "rest_seconds": 75,
      "progression_strategy": "Aumento linear semanal.",
      "safety_notes": ["Aquecer antes de cada treino"]
    }
  JSON

  describe "#call" do
    context "with valid JSON" do
      subject(:result) { described_class.new(VALID_JSON).call }

      it "returns valid: true" do
        expect(result[:valid]).to be true
      end

      it "extracts training_method" do
        expect(result[:data][:training_method]).to eq("upper_lower")
      end

      it "extracts personalization_reason" do
        expect(result[:data][:personalization_reason]).to include("hipertrofia")
      end

      it "extracts user_explanation" do
        expect(result[:data][:user_explanation]).to be_present
      end

      it "normalizes week_structure to valid groups only" do
        groups = result[:data][:week_structure].flat_map { |d| d[:muscle_groups] }
        expect(groups).to include("chest", "back", "legs", "core")
      end

      it "clamps sets to valid range" do
        expect(result[:data][:sets_reps][:sets]).to be_between(1, 8)
      end
    end

    context "with JSON inside markdown code block" do
      let(:markdown_response) { "Here is your plan:\n```json\n#{VALID_JSON}\n```" }

      it "extracts and parses the JSON" do
        result = described_class.new(markdown_response).call
        expect(result[:valid]).to be true
        expect(result[:data][:training_method]).to eq("upper_lower")
      end
    end

    context "with invalid training_method" do
      let(:bad_json) { VALID_JSON.gsub('"upper_lower"', '"invalid_method"') }

      it "returns valid: false with error" do
        result = described_class.new(bad_json).call
        expect(result[:valid]).to be false
        expect(result[:errors].first).to include("training_method")
      end
    end

    context "with empty week_structure" do
      let(:empty_struct) { VALID_JSON.gsub('"week_structure": [', '"week_structure": [').gsub(/\{ "name".*?\},\n.*?\}/, "") }

      it "returns valid: false" do
        bad = '{"training_method":"full_body","week_structure":[],"sets":3,"reps":10,"rest_seconds":90}'
        result = described_class.new(bad).call
        expect(result[:valid]).to be false
      end
    end

    context "with nil response" do
      it "returns valid: false" do
        result = described_class.new(nil).call
        expect(result[:valid]).to be false
      end
    end

    context "with invalid JSON" do
      it "returns valid: false with parse error" do
        result = described_class.new("not json at all").call
        expect(result[:valid]).to be false
      end
    end
  end
end
