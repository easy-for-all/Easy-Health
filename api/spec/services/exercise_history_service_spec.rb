require "rails_helper"

RSpec.describe ExerciseHistoryService do
  let(:user) { create(:user) }
  let(:exercise) { Exercise.create!(name: "Rosca com Halteres", exercise_type: "musculacao", muscle_group: "biceps") }
  let(:service) { described_class.new(user: user, exercise_id: exercise.id) }

  def create_exercise_session(status:, workout_session_status: "completed", completed_at: Time.current)
    workout_session = user.workout_sessions.create!(
      status: workout_session_status,
      completion_status: (workout_session_status == "completed" ? "completed" : "completed_partial"),
      duration_minutes: 40,
      completed_at: completed_at,
      exercise_logs: []
    )
    workout_session.exercise_sessions.create!(
      exercise: exercise, order_index: 0, exercise_kind: "strength",
      status: status, started_at: completed_at, completed_at: (completed_at if status == "completed")
    )
  end

  describe "#last_execution_label / #last_completed_at" do
    it "returns 'primeira vez' when there is no completed history" do
      expect(service.last_execution_label).to eq("Primeira vez neste exercício")
      expect(service.last_completed_at).to be_nil
    end

    it "never considers an in_progress session as history (the reported bug)" do
      create_exercise_session(status: "completed", workout_session_status: "completed", completed_at: 5.days.ago)
      create_exercise_session(status: "in_progress", workout_session_status: "in_progress", completed_at: Time.current)

      expect(service.last_execution_label).to eq("Há 5 dias")
    end

    it "ignores cancelled sessions entirely" do
      create_exercise_session(status: "completed", workout_session_status: "completed", completed_at: 5.days.ago)
      cancelled_session = user.workout_sessions.create!(status: "cancelled", completion_status: "abandoned", exercise_logs: [])
      cancelled_session.exercise_sessions.create!(exercise: exercise, order_index: 0, exercise_kind: "strength", status: "completed", started_at: Time.current, completed_at: Time.current)

      expect(service.last_execution_label).to eq("Há 5 dias")
    end

    it "says 'feito hoje' for a session completed today" do
      create_exercise_session(status: "completed", completed_at: Time.current)
      expect(service.last_execution_label).to eq("Feito hoje")
    end

    it "says 'feito ontem' for a session completed yesterday" do
      create_exercise_session(status: "completed", completed_at: 1.day.ago)
      expect(service.last_execution_label).to eq("Feito ontem")
    end
  end

  describe "#last_used_weight" do
    it "returns the last working (non-warmup) set weight, ignoring warmup sets" do
      exercise_session = create_exercise_session(status: "completed")
      exercise_session.exercise_sets.create!(set_number: 1, weight_kg: 5, reps: 12, is_warmup: true, completed_at: Time.current)
      exercise_session.exercise_sets.create!(set_number: 2, weight_kg: 15, reps: 10, is_warmup: false, completed_at: Time.current)

      expect(service.last_used_weight).to eq(15.0)
    end

    it "falls back to the warmup weight when there is no working set at all" do
      exercise_session = create_exercise_session(status: "completed")
      exercise_session.exercise_sets.create!(set_number: 1, weight_kg: 5, reps: 12, is_warmup: true, completed_at: Time.current)

      expect(service.last_used_weight).to eq(5.0)
    end

    it "falls back to legacy exercise_logs JSONB when no relational data exists for this exercise" do
      user.workout_sessions.create!(
        status: "completed", completion_status: "completed", completed_at: 2.days.ago, duration_minutes: 40,
        exercise_logs: [ { "exercise_id" => exercise.id, "weight_by_set" => [ 20.0 ], "reps" => [ 8 ], "is_warmup_by_set" => [ false ] } ]
      )

      expect(service.last_used_weight).to eq(20.0)
    end
  end

  describe "#suggested_starting_weight / #progression_reason with block context" do
    before do
      user.workout_sessions.create!(
        status: "completed", completion_status: "completed", completed_at: 10.days.ago, duration_minutes: 40,
        exercise_logs: [ { "exercise_id" => exercise.id, "weight_by_set" => [ 20.0 ], "reps" => [ 10 ], "planned_sets" => 1 } ]
      )
      user.workout_sessions.create!(
        status: "completed", completion_status: "completed", completed_at: 2.days.ago, duration_minutes: 40,
        exercise_logs: [ { "exercise_id" => exercise.id, "weight_by_set" => [ 20.0 ], "reps" => [ 10 ], "planned_sets" => 1 } ]
      )
    end

    it "suggests the next realistic load when the exercise is a single block (default)" do
      expect(service.suggested_starting_weight).to eq(22.5)
      expect(service.progression_reason).not_to include("Ajustado para bloco")
    end

    it "discounts to ~90% when performed inside a superset" do
      superset_service = described_class.new(user: user, exercise_id: exercise.id, block_type: "superset")
      expect(superset_service.suggested_starting_weight).to eq(20.0)
      expect(superset_service.progression_reason).to include("Ajustado para bloco: superset (~90% da carga isolada)")
    end

    it "discounts to ~77.5% when performed inside a circuit" do
      circuit_service = described_class.new(user: user, exercise_id: exercise.id, block_type: "circuit")
      expect(circuit_service.suggested_starting_weight).to eq(17)
    end

    it "never invents a weight when there is no history at all" do
      other_exercise = Exercise.create!(name: "Outro Exercício", exercise_type: "musculacao", muscle_group: "back")
      no_history_service = described_class.new(user: user, exercise_id: other_exercise.id, block_type: "superset")
      expect(no_history_service.suggested_starting_weight).to be_nil
    end
  end

  describe "#personal_record" do
    it "picks the highest working weight and excludes warmup sets" do
      s1 = create_exercise_session(status: "completed", completed_at: 10.days.ago)
      s1.exercise_sets.create!(set_number: 1, weight_kg: 50, reps: 1, is_warmup: true, completed_at: 10.days.ago)
      s1.exercise_sets.create!(set_number: 2, weight_kg: 20, reps: 8, is_warmup: false, completed_at: 10.days.ago)

      s2 = create_exercise_session(status: "completed", completed_at: 2.days.ago)
      s2.exercise_sets.create!(set_number: 1, weight_kg: 22, reps: 6, is_warmup: false, completed_at: 2.days.ago)

      record = service.personal_record
      expect(record[:max_weight_kg]).to eq(22.0)
    end
  end
end
