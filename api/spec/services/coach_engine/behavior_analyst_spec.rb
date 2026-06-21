require "rails_helper"

RSpec.describe CoachEngine::BehaviorAnalyst do
  let(:user) { create(:user) }
  let(:health_profile) { create(:health_profile, user: user, training_days_per_week: 3) }
  let(:fitness_profile) { FitnessProfile.create!(user: user, adherence_score: 6, consistency_score: 6) }

  it "keeps behavior unknown until there are three completed sessions" do
    2.times do |index|
      user.workout_sessions.create!(completed_at: (index + 1).days.ago, duration_minutes: 30, exercise_logs: [])
    end

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["behavior_pattern"]).to eq("unknown")
    expect(result["confidence"]).to eq(0.2)
  end

  it "infers skipped lower body only from linked plan sessions" do
    plan = user.workout_plans.create!(active: true)
    day = plan.workout_days.create!(name: "Inferior", day_of_week: 1, position: 1)
    lower_exercise = Exercise.create!(name: "Leg Press", exercise_type: "musculacao", muscle_group: "legs")
    cardio_exercise = Exercise.create!(name: "Esteira", exercise_type: "cardio")
    day.workout_day_exercises.create!(exercise: lower_exercise, sets: 3, reps: 10, rest_seconds: 90, order_index: 0)

    3.times do |index|
      user.workout_sessions.create!(
        workout_day: day,
        completed_at: (index + 1).days.ago,
        duration_minutes: 30,
        exercise_logs: [ { "exercise_id" => cardio_exercise.id } ]
      )
    end

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["behavior_pattern"]).to eq("skips_lower_body")
    expect(result["avoided_patterns"]).to include("skips_lower_body")
  end

  it "treats accepted suggestions as a weak substitution preference signal" do
    exercise = Exercise.create!(name: "Remada", exercise_type: "musculacao", muscle_group: "back")
    3.times do |index|
      user.workout_sessions.create!(completed_at: (index + 1).days.ago, duration_minutes: 30, exercise_logs: [])
    end
    user.exercise_suggestion_logs.create!(suggested_exercise: exercise, event_type: "suggestion_accepted", accepted: true)

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["preferred_patterns"]).to include("responds_to_substitution_feedback")
    expect(result["adherence_notes"].join).to include("preferência")
  end
end
