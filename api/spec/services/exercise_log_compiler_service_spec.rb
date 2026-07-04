require "rails_helper"

RSpec.describe ExerciseLogCompilerService do
  let(:user) { create(:user) }
  let(:exercise) { Exercise.create!(name: "Rosca com Halteres", exercise_type: "musculacao", muscle_group: "biceps") }
  let(:cardio_exercise) { Exercise.create!(name: "Corrida", exercise_type: "corrida") }

  let(:workout_session) do
    user.workout_sessions.create!(status: "in_progress")
  end

  describe "#call" do
    it "compiles a strength exercise session into the legacy exercise_logs shape, ordered by order_index" do
      exercise_session = workout_session.exercise_sessions.create!(
        exercise: exercise,
        order_index: 0,
        exercise_kind: "strength",
        planned_sets: 3,
        rest_seconds: 60,
        feeling: "bom",
        started_at: Time.current
      )
      exercise_session.exercise_sets.create!(set_number: 1, weight_kg: 10, reps: 12, is_warmup: true, completed_at: Time.current)
      exercise_session.exercise_sets.create!(set_number: 2, weight_kg: 15, reps: 10, is_warmup: false, completed_at: Time.current)
      exercise_session.exercise_sets.create!(set_number: 3, weight_kg: 15, reps: 9, is_warmup: false, completed_at: Time.current)

      logs = described_class.new(workout_session).call

      expect(logs.size).to eq(1)
      log = logs.first
      expect(log["exercise_id"]).to eq(exercise.id)
      expect(log["name"]).to eq("Rosca com Halteres")
      expect(log["weight_by_set"]).to eq([ 10.0, 15.0, 15.0 ])
      expect(log["reps"]).to eq([ 12, 10, 9 ])
      expect(log["is_warmup_by_set"]).to eq([ true, false, false ])
      expect(log["sets"]).to eq(3)
    end

    it "compiles cardio/timed exercise sessions without any exercise_sets" do
      workout_session.exercise_sessions.create!(
        exercise: cardio_exercise,
        order_index: 0,
        exercise_kind: "cardio",
        duration_minutes: 20,
        intensity: "moderado",
        started_at: Time.current
      )

      logs = described_class.new(workout_session).call

      expect(logs.size).to eq(1)
      expect(logs.first["duration_minutes"]).to eq(20)
      expect(logs.first["intensity"]).to eq("moderado")
      expect(logs.first["weight_by_set"]).to be_nil
    end

    it "preserves execution order via order_index" do
      workout_session.exercise_sessions.create!(exercise: cardio_exercise, order_index: 1, exercise_kind: "cardio", started_at: Time.current)
      workout_session.exercise_sessions.create!(exercise: exercise, order_index: 0, exercise_kind: "strength", started_at: Time.current)

      logs = described_class.new(workout_session).call

      expect(logs.map { |l| l["exercise_id"] }).to eq([ exercise.id, cardio_exercise.id ])
    end
  end
end
