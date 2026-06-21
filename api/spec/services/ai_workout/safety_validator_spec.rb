require "rails_helper"

RSpec.describe AiWorkout::SafetyValidator do
  let(:beginner_persona)  { "sedentary_beginner" }
  let(:intermediate_persona) { "hypertrophy_intermediate" }

  def build_data(sets: 3, intensity: nil, safety_notes: [], week_structure: [])
    {
      sets_reps:     { sets: sets },
      intensity_level: intensity,
      safety_notes:  safety_notes,
      week_structure: week_structure
    }
  end

  def build_profile(persona: "general_health", risk_score: 3.0, limitations: [])
    instance_double(
      FitnessProfile,
      primary_persona:      persona,
      risk_score:           risk_score,
      physical_limitations: limitations
    )
  end

  subject(:validator) do
    described_class.new(
      parsed_data:     build_data,
      fitness_profile: build_profile
    )
  end

  describe "#call" do
    context "with valid data and no risks" do
      it "returns valid: true with no violations" do
        result = validator.call
        expect(result[:valid]).to be true
        expect(result[:violations]).to be_empty
      end
    end

    context "with volume absurdo" do
      subject(:validator) do
        described_class.new(
          parsed_data:     build_data(sets: 9),
          fitness_profile: build_profile
        )
      end

      it "returns a violation about excessive sets" do
        result = validator.call
        expect(result[:valid]).to be false
        expect(result[:violations].first).to include("Volume excessivo")
      end
    end

    context "with high intensity and high risk_score" do
      subject(:validator) do
        described_class.new(
          parsed_data:     build_data(intensity: "high"),
          fitness_profile: build_profile(risk_score: 7.5)
        )
      end

      it "returns a violation about high intensity" do
        result = validator.call
        expect(result[:valid]).to be false
        expect(result[:violations].first).to include("Intensidade 'high'")
      end
    end

    context "with beginner persona and high risk and no warmup note" do
      subject(:validator) do
        described_class.new(
          parsed_data:     build_data(safety_notes: []),
          fitness_profile: build_profile(persona: beginner_persona, risk_score: 6.0)
        )
      end

      it "adds a warning about missing warmup note" do
        result = validator.call
        expect(result[:warnings]).to include(a_string_including("aquecimento"))
      end
    end

    context "with beginner persona and warmup note present" do
      subject(:validator) do
        described_class.new(
          parsed_data:     build_data(safety_notes: ["Aqueça 5 minutos antes"]),
          fitness_profile: build_profile(persona: beginner_persona, risk_score: 6.0)
        )
      end

      it "does not warn about warmup" do
        result = validator.call
        expect(result[:warnings]).not_to include(a_string_including("aquecimento"))
      end
    end

    context "with nil parsed_data" do
      subject(:validator) do
        described_class.new(
          parsed_data:     nil,
          fitness_profile: build_profile
        )
      end

      it "returns valid: true (skips validation)" do
        result = validator.call
        expect(result[:valid]).to be true
      end
    end
  end
end
