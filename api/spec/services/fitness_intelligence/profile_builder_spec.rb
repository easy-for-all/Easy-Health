require "rails_helper"

RSpec.describe FitnessIntelligence::ProfileBuilder do
  let(:user) { create(:user) }
  let!(:health_profile) do
    create(
      :health_profile,
      user: user,
      age: 32,
      fitness_level: "beginner",
      goal: "gain_muscle",
      activity_preferences: [ "musculacao" ],
      training_location: "gym",
      limitations: [ "ombro" ]
    )
  end

  it "builds one auditable profile from existing non-PII fitness inputs" do
    exercise = Exercise.create!(name: "Supino", exercise_type: "musculacao")
    user.user_favorite_exercises.create!(exercise: exercise)
    user.health_data_points.create!(
      field_name: "body_fat_pct",
      value: 22,
      source_type: "exam",
      status: "confirmed",
      raw_text: "conteúdo sensível do exame"
    )

    profile = described_class.new(user).call(source: "spec")

    expect(profile).to be_persisted
    expect(profile.primary_persona).to eq("hypertrophy_beginner")
    expect(profile.training_archetype).to eq("aesthetic_hypertrophy")
    expect(profile.behavior_pattern).to eq("unknown")
    expect(profile.preferred_exercises).to eq([ exercise.id ])
    expect(profile.physical_limitations).to eq([ "ombro" ])
    expect(profile.metadata.dig("source_counts", "health_metric_types")).to eq([ "body_fat_pct" ])
    expect(profile.metadata.to_json).not_to include("conteúdo sensível do exame")
    expect(user.user_events.where(event_name: "fitness_profile_created")).to exist
  end

  it "recalculates idempotently instead of duplicating the profile" do
    first = described_class.new(user).call(source: "spec")
    second = described_class.new(user).call(source: "spec")

    expect(second.id).to eq(first.id)
    expect(user.reload.fitness_profile).to eq(first)
    expect(FitnessProfile.where(user: user).count).to eq(1)
    expect(user.user_events.where(event_name: "fitness_profile_recalculated").count).to eq(1)
  end

  it "does not invent a profile when the user has no health profile" do
    user_without_profile = create(:user)

    expect(described_class.new(user_without_profile).call).to be_nil
    expect(user_without_profile.fitness_profile).to be_nil
  end

  it "copies structured preferences without adding exercise names to metadata" do
    exercise = Exercise.create!(name: "Remada", exercise_type: "musculacao", muscle_group: "back")
    user.user_favorite_exercises.create!(exercise: exercise)
    health_profile.update!(
      preferred_body_focus: [ "back" ],
      preferred_training_styles: [ "traditional_strength" ],
      available_equipment: [ "dumbbell" ],
      avoided_exercise_ids: [ exercise.id ]
    )

    profile = described_class.new(user).call(source: "spec_preferences")

    expect(profile.preferred_body_focus).to eq([ "back" ])
    expect(profile.preferred_training_styles).to eq([ "traditional_strength" ])
    expect(profile.available_equipment).to eq([ "dumbbell" ])
    expect(profile.avoided_exercises).to eq([ exercise.id ])
    expect(profile.metadata.to_json).not_to include("Remada")
  end
end
