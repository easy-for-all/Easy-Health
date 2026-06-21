require "rails_helper"

RSpec.describe CoachEngine::WorkoutStrategist do
  let(:user) { create(:user) }
  let(:health_profile) do
    create(
      :health_profile,
      user: user,
      fitness_level: "intermediate",
      goal: "gain_muscle",
      training_days_per_week: 3,
      session_duration_minutes: 45
    )
  end
  let(:fitness_profile) { FitnessProfile.create!(user: user, fitness_level: "intermediate") }

  def strategy
    described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call
  end

  def audit(behavior: {}, progress: {}, risk: {})
    fitness_profile.update!(metadata: {
      "coach_engine" => {
        "behavior" => behavior,
        "progress" => progress,
        "risk" => risk
      }
    })
  end

  it "keeps glute focus while preserving upper-body balance" do
    fitness_profile.update!(training_archetype: "glute_focused", primary_persona: "hypertrophy_intermediate")

    result = strategy

    expect(result["primary_focus"]).to include("glutes", "legs")
    expect(result["secondary_focus"]).to include("chest", "back")
    expect(result["training_split"]).to eq("full_body")
  end

  it "uses a strength-focused upper/lower strategy for four weekly sessions" do
    health_profile.update!(goal: "strength", training_days_per_week: 4)
    fitness_profile.update!(training_archetype: "strength_focused")

    result = strategy

    expect(result["training_split"]).to eq("upper_lower")
    expect(result.dig("strength_strategy", "reps")).to eq(6)
    expect(result["progression_model"]).to eq("adaptation")
  end

  it "uses cardio and mobility for a mobility archetype" do
    health_profile.update!(goal: "mobility")
    fitness_profile.update!(training_archetype: "mobility_focused")

    result = strategy

    expect(result["training_split"]).to eq("cardio_mobility")
    expect(result.dig("mobility_strategy", "enabled")).to be(true)
  end

  it "lets confident real behavior reduce declared duration and frequency" do
    health_profile.update!(training_days_per_week: 4, session_duration_minutes: 60)
    fitness_profile.update!(behavior_pattern: "low_adherence")
    audit(behavior: {
      "confidence" => 0.8,
      "preferred_patterns" => [ "consistent_short_sessions" ],
      "avoided_patterns" => []
    })

    result = strategy

    expect(result["weekly_frequency"]).to eq(3)
    expect(result["session_duration_minutes"]).to eq(35)
    expect(result["notes_for_generator"]).to include("behavior_overrides_declared_preferences")
  end

  it "returns conservative safeguards for pregnancy without exposing free text" do
    health_profile.update!(training_context: "pregnant")
    fitness_profile.update!(risk_score: 8)
    audit(risk: {
      "forbidden_exercise_patterns" => %w[high_impact aggressive_core_loading],
      "required_regressions" => [ "low_impact_variation" ]
    })

    result = strategy

    expect(result["intensity_level"]).to eq("low")
    expect(result["forbidden_exercises"]).to include("high_impact", "aggressive_core_loading")
    expect(result["recommended_exercise_patterns"]).to include("low_impact_variation")
    expect(result.to_json).not_to include("gestante")
  end

  it "uses a conservative, non-inferred fallback without a fitness profile" do
    result = described_class.new(user: user).call

    expect(result).to include(
      "strategy_version" => "v1",
      "primary_persona" => "general_health",
      "training_archetype" => "balanced_full_body"
    )
    expect(result["notes_for_generator"]).to include("profile_data_insufficient")
  end
end
