require "rails_helper"

RSpec.describe "Api::V1::WorkoutPlans", type: :request do
  let(:user) { create(:user, paid_plan: true) }
  let(:exercise) { Exercise.create!(name: "Rosca com Halteres", exercise_type: "musculacao", muscle_group: "biceps") }
  let(:plan) { user.workout_plans.create!(active: true) }
  let(:day) do
    plan.workout_days.create!(name: "Treino A", day_of_week: Date.current.wday)
  end

  before do
    sign_in user
    day.workout_day_exercises.create!(exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 0)
  end

  describe "GET /api/v1/workout_days/:id" do
    it "does not surface an in-progress or cancelled session as the exercise's last performance" do
      user.workout_sessions.create!(
        completed_at: 5.days.ago, duration_minutes: 40, status: "completed",
        exercise_logs: [ { "exercise_id" => exercise.id, "weight_by_set" => [ 12.0 ], "reps" => [ 10 ] } ]
      )
      # The current, still-in-progress attempt at the same workout, "completed" moments ago,
      # must never eclipse the real completed session above - this is the reported bug.
      user.workout_sessions.create!(
        completed_at: Time.current, duration_minutes: 1, status: "in_progress",
        exercise_logs: []
      )
      user.workout_sessions.create!(status: "cancelled", completion_status: "abandoned", exercise_logs: [ { "exercise_id" => exercise.id, "weight_by_set" => [ 999.0 ], "reps" => [ 1 ] } ])

      get "/api/v1/workout_days/#{day.id}"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      exercise_json = body["day"]["exercises"].first
      expect(Time.parse(exercise_json["last_performed_at"])).to be_within(1.minute).of(5.days.ago)
      # The reported bug, restated through the new explicit fields: the in-progress/cancelled
      # attempts must never surface as "last time"/"last weight", only the real completed session.
      expect(exercise_json["last_execution_label"]).to eq("Há 5 dias")
      expect(exercise_json["last_weight_kg"]).to eq(12.0)
    end

    it "exposes planned_weight_kg from the workout_day_exercise" do
      day.workout_day_exercises.first.update!(planned_weight: 20)

      get "/api/v1/workout_days/#{day.id}"

      exercise_json = JSON.parse(response.body)["day"]["exercises"].first
      expect(exercise_json["planned_weight_kg"].to_f).to eq(20.0)
    end

    it "says 'Primeira vez neste exercício' when there is no history at all" do
      get "/api/v1/workout_days/#{day.id}"

      exercise_json = JSON.parse(response.body)["day"]["exercises"].first
      expect(exercise_json["last_execution_label"]).to eq("Primeira vez neste exercício")
      expect(exercise_json["last_weight_kg"]).to be_nil
    end

    it "wraps a legacy single exercise in a single block by default" do
      get "/api/v1/workout_days/#{day.id}"

      exercise_json = JSON.parse(response.body)["day"]["exercises"].first
      expect(exercise_json["block_type"]).to eq("single")
      expect(exercise_json["block_rounds"]).to eq(1)
      expect(exercise_json["position_in_block"]).to eq(0)
    end

    it "exposes block_type, block_id and position_in_block for a superset" do
      exercise_b = Exercise.create!(name: "Remada Baixa", exercise_type: "musculacao", muscle_group: "back")
      block = day.workout_blocks.create!(block_type: "superset", position: 1, rounds: 3, rest_between_rounds_seconds: 90)
      wde_a = day.workout_day_exercises.first
      wde_a.update!(workout_block: block, position_in_block: 0)
      day.workout_day_exercises.create!(
        exercise: exercise_b, sets: 3, reps: 10, rest_seconds: 60, order_index: 1,
        workout_block: block, position_in_block: 1
      )

      get "/api/v1/workout_days/#{day.id}"

      exercises = JSON.parse(response.body)["day"]["exercises"]
      a1 = exercises.find { |e| e["exercise_id"] == exercise.id }
      a2 = exercises.find { |e| e["exercise_id"] == exercise_b.id }

      expect(a1["block_type"]).to eq("superset")
      expect(a1["block_id"]).to eq(block.id)
      expect(a1["position_in_block"]).to eq(0)
      expect(a1["block_rounds"]).to eq(3)
      expect(a1["block_rest_between_rounds_seconds"]).to eq(90)
      expect(a2["block_id"]).to eq(block.id)
      expect(a2["position_in_block"]).to eq(1)
    end

    it "does not surface a cancelled session as the day's last_completed_at" do
      user.workout_sessions.create!(workout_day: day, completed_at: 3.days.ago, duration_minutes: 40, status: "completed", exercise_logs: [])
      user.workout_sessions.create!(workout_day: day, status: "cancelled", completion_status: "abandoned", exercise_logs: [])

      get "/api/v1/workout_days/#{day.id}"

      body = JSON.parse(response.body)
      expect(Time.parse(body["day"]["last_completed_at"])).to be_within(1.minute).of(3.days.ago)
    end
  end

  describe "POST /api/v1/workout_plan/regenerate muscle selection" do
    before do
      create(:health_profile, user: user, training_days_per_week: 3)
      allow_any_instance_of(WorkoutPlanGeneratorService).to receive(:call) do
        user.workout_plans.update_all(active: false)
        new_plan = user.workout_plans.create!(active: true)
        new_plan.workout_days.create!(name: "Treino A", day_of_week: Date.current.wday)
        new_plan
      end
      allow_any_instance_of(WorkoutPlanGeneratorService).to receive(:plan_summary).and_return({})
    end

    it "persists the selected groups and priorities, dropping invalid values" do
      post "/api/v1/workout_plan/regenerate", params: {
        modality: "musculacao",
        selected_muscles: [ "chest", "triceps", "not_a_muscle" ],
        muscle_priorities: { "chest" => "high", "triceps" => "bogus", "legs" => "avoid" }
      }

      expect(response).to have_http_status(:ok)
      profile = user.health_profile.reload
      expect(profile.selected_muscle_groups).to match_array(%w[chest triceps])
      # Só grupos e níveis válidos sobrevivem.
      expect(profile.muscle_priorities).to eq({ "chest" => "high", "legs" => "avoid" })
    end

    it "forwards the sanitized selection to the generator service" do
      expect(WorkoutPlanGeneratorService).to receive(:new).with(
        user, hash_including(selected_muscles: %w[chest], muscle_priorities: { "chest" => "high" })
      ).and_call_original

      post "/api/v1/workout_plan/regenerate", params: {
        modality: "musculacao",
        selected_muscles: [ "chest" ],
        muscle_priorities: { "chest" => "high" }
      }

      expect(response).to have_http_status(:ok)
    end
  end
end
