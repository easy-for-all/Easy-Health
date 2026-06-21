require "rails_helper"

RSpec.describe FitnessIntelligence::ScoreCalculator do
  let(:now) { Time.zone.parse("2026-06-21 12:00:00") }
  let(:user) { create(:user) }
  let(:health_profile) do
    create(
      :health_profile,
      user: user,
      age: 30,
      weight_kg: 70,
      height_cm: 175,
      fitness_level: "beginner",
      goal: "gain_muscle",
      training_days_per_week: 3,
      activity_preferences: [ "musculacao" ]
    )
  end

  subject(:result) { described_class.new(user: user, health_profile: health_profile, now: now).call }

  it "uses the explicit neutral fallback when no workout history exists" do
    scores = result[:scores]

    expect(scores).to include(
      consistency_score: 0,
      adherence_score: 5,
      recovery_score: 5,
      mobility_score: 5,
      motivation_score: 5,
      behavior_confidence_score: 0
    )
    expect(result.dig(:breakdown, :score_status, :adherence_score)).to eq("insufficient_data")
  end

  it "raises consistency and behavior confidence from recurring completed sessions" do
    10.times do |index|
      user.workout_sessions.create!(
        completed_at: now - (index * 2).days,
        duration_minutes: 35,
        exercise_logs: [ { "exercise_id" => index + 1 } ]
      )
    end

    scores = result[:scores]
    expect(scores[:consistency_score]).to be > 7
    expect(scores[:behavior_confidence_score]).to be > 5
    expect(scores[:adherence_score]).to be > 7
  end

  it "adds conservative risk for declared limitations and adult BMI caution without diagnosing" do
    health_profile.update!(weight_kg: 100, height_cm: 170, limitations: [ "joelho" ])

    expect(result[:scores][:risk_score]).to eq(9)
  end
end
