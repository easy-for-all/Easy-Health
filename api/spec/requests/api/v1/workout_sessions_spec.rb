require "rails_helper"

RSpec.describe "Api::V1::WorkoutSessions", type: :request do
  let(:user) { create(:user, paid_plan: true) }

  before { sign_in user }

  def session_payload(overrides = {})
    {
      source: "web",
      duration_minutes: 45,
      completed_at: Time.current.iso8601,
      exercise_logs: []
    }.merge(overrides)
  end

  describe "POST /api/v1/workout_sessions" do
    it "creates a completed session with default status" do
      post "/api/v1/workout_sessions", params: session_payload

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["completion_status"]).to eq("completed")
    end

    it "persists completion_status: completed_partial" do
      post "/api/v1/workout_sessions", params: session_payload(
        completion_status: "completed_partial",
        completion_rate: 66.67,
        completed_sets_count: 8,
        planned_sets_count: 12,
        skipped_exercises: [ { exercise_id: 5, name: "Agachamento", planned_sets: 4 } ]
      )

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["completion_status"]).to eq("completed_partial")
      expect(body["completion_rate"]).to eq("66.67")
      expect(body["completed_sets_count"]).to eq(8)
      expect(body["planned_sets_count"]).to eq(12)
      expect(body["skipped_exercises"].length).to eq(1)
    end

    it "persists extra_block_type and extra_block_data" do
      post "/api/v1/workout_sessions", params: session_payload(
        extra_block_type: "cardio",
        extra_block_data: { modality: "bike", duration_minutes: 20, intensity: "moderate" },
        extra_started_at: 30.minutes.ago.iso8601,
        extra_completed_at: 10.minutes.ago.iso8601
      )

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["extra_block_type"]).to eq("cardio")
      expect(body["extra_block_data"]["modality"]).to eq("bike")
    end

    it "returns 422 for invalid completion_status" do
      post "/api/v1/workout_sessions", params: session_payload(completion_status: "invalid")

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "GET /api/v1/workout_sessions/load_suggestion" do
    it "returns maintain when no exercise history exists" do
      get "/api/v1/workout_sessions/load_suggestion", params: { exercise_id: 999 }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["action"]).to eq("maintain")
      expect(body["reason"]).to be_present
    end

    it "returns 400 when exercise_id is missing" do
      get "/api/v1/workout_sessions/load_suggestion"

      expect(response).to have_http_status(:bad_request)
    end

    it "returns increase suggestion after consistent sessions" do
      log = {
        "exercise_id" => 42,
        "name" => "Supino",
        "weight_by_set" => [ 15.0, 15.0, 15.0 ],
        "reps" => [ 10, 10, 10 ],
        "planned_sets" => 3
      }
      user.workout_sessions.create!(completed_at: 7.days.ago, duration_minutes: 45, completion_status: "completed", exercise_logs: [ log ])
      user.workout_sessions.create!(completed_at: 3.days.ago, duration_minutes: 45, completion_status: "completed", exercise_logs: [ log ])

      get "/api/v1/workout_sessions/load_suggestion", params: { exercise_id: 42 }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["action"]).to eq("increase")
      expect(body["suggested_weight"]).to be > 15.0
    end
  end
end
