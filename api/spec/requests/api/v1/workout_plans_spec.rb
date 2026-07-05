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

    it "does not surface a cancelled session as the day's last_completed_at" do
      user.workout_sessions.create!(workout_day: day, completed_at: 3.days.ago, duration_minutes: 40, status: "completed", exercise_logs: [])
      user.workout_sessions.create!(workout_day: day, status: "cancelled", completion_status: "abandoned", exercise_logs: [])

      get "/api/v1/workout_days/#{day.id}"

      body = JSON.parse(response.body)
      expect(Time.parse(body["day"]["last_completed_at"])).to be_within(1.minute).of(3.days.ago)
    end
  end
end
