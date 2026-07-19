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

    it "persists block_type/block_id/position_in_block per exercise_logs entry (superset rounds)" do
      post "/api/v1/workout_sessions", params: session_payload(
        exercise_logs: [
          {
            workout_day_exercise_id: 1, exercise_id: 10, name: "Supino Inclinado",
            weight_kg: 20, weight_by_set: [ 20, 20, 20 ], reps: [ 10, 10, 8 ], is_warmup_by_set: [ false, false, false ],
            planned_sets: 3, sets: 3, rest_seconds: 0,
            block_type: "superset", block_id: 7, position_in_block: 0
          },
          {
            workout_day_exercise_id: 2, exercise_id: 11, name: "Remada Baixa",
            weight_kg: 15, weight_by_set: [ 15, 15, 15 ], reps: [ 12, 12, 10 ], is_warmup_by_set: [ false, false, false ],
            planned_sets: 3, sets: 3, rest_seconds: 90,
            block_type: "superset", block_id: 7, position_in_block: 1
          }
        ]
      )

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      a1 = body["exercise_logs"].find { |l| l["exercise_id"].to_i == 10 }
      a2 = body["exercise_logs"].find { |l| l["exercise_id"].to_i == 11 }

      expect(a1["block_type"]).to eq("superset")
      expect(a1["block_id"].to_i).to eq(7)
      expect(a1["position_in_block"].to_i).to eq(0)
      expect(a1["weight_by_set"].size).to eq(3) # one entry per round, no series lost
      expect(a2["position_in_block"].to_i).to eq(1)
    end

    it "returns 422 for invalid completion_status" do
      post "/api/v1/workout_sessions", params: session_payload(completion_status: "invalid")

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "maps completion_status: abandoned to the technical status cancelled" do
      post "/api/v1/workout_sessions", params: session_payload(completion_status: "abandoned")

      expect(response).to have_http_status(:created)
      expect(WorkoutSession.last.status).to eq("cancelled")
    end

    it "maps completion_status: completed_partial to the technical status completed" do
      post "/api/v1/workout_sessions", params: session_payload(completion_status: "completed_partial")

      expect(response).to have_http_status(:created)
      expect(WorkoutSession.last.status).to eq("completed")
    end
  end

  describe "regression: an abandoned session never counts as history" do
    let(:log) do
      {
        "exercise_id" => 42,
        "name" => "Rosca com Halteres",
        "weight_by_set" => [ 12.0, 12.0 ],
        "reps" => [ 10, 10 ],
        "is_warmup_by_set" => [ false, false ]
      }
    end

    it "excludes cancelled (abandoned) sessions from last_performances, even when more recent than a completed one" do
      user.workout_sessions.create!(completed_at: 10.days.ago, duration_minutes: 40, status: "completed", exercise_logs: [ log.merge("weight_by_set" => [ 15.0, 15.0 ]) ])
      user.workout_sessions.create!(completed_at: Time.current, duration_minutes: 2, status: "cancelled", completion_status: "abandoned", exercise_logs: [ log ])

      get "/api/v1/workout_sessions/last_performances", params: { exercise_ids: "42" }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["42"]["weight_by_set"]).to eq([ 15.0, 15.0 ])
    end

    it "excludes cancelled sessions from personal_records" do
      user.workout_sessions.create!(completed_at: Time.current, duration_minutes: 2, status: "cancelled", completion_status: "abandoned", exercise_logs: [ log.merge("weight_by_set" => [ 999.0 ]) ])

      get "/api/v1/workout_sessions/personal_records"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to be_empty
    end

    it "excludes cancelled sessions from today" do
      user.workout_sessions.create!(completed_at: Time.current, duration_minutes: 2, status: "cancelled", completion_status: "abandoned", exercise_logs: [])

      get "/api/v1/workout_sessions/today"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq({})
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

  describe "real-time execution lifecycle" do
    let(:exercise) do
      Exercise.create!(
        name: "Rosca com Halteres",
        exercise_type: "musculacao",
        muscle_group: "biceps",
        gif_url: "/exercise-images/gifdotreino/biceps/rosca-com-halteres.gif"
      )
    end

    # This app's request-spec session does not carry the signed-in user across
    # multiple sequential requests within the same example, so each call in a
    # multi-step flow re-authenticates explicitly.
    def authed_post(path, as:, params: {})
      sign_in as
      post path, params: params
    end

    def authed_get(path, as:)
      sign_in as
      get path
    end

    def authed_patch(path, as:, params: {})
      sign_in as
      patch path, params: params
    end

    describe "POST /api/v1/workout_sessions/start" do
      it "creates an in_progress session without running completion side effects" do
        expect(FitnessIntelligence).not_to receive(:recalculate_safely)

        authed_post "/api/v1/workout_sessions/start", as: user, params: { source: "web" }

        expect(response).to have_http_status(:created)
        body = JSON.parse(response.body)
        expect(body["status"]).to eq("in_progress")
        expect(WorkoutSession.find(body["id"]).completed_at).to be_nil
      end

      it "tracks first_workout_started for the user's first session" do
        authed_post "/api/v1/workout_sessions/start", as: user, params: { source: "web" }

        expect(response).to have_http_status(:created)
        session_id = JSON.parse(response.body)["id"]
        event = UserEvent.find_by(user: user, event_name: "first_workout_started")
        expect(event).to be_present
        expect(event.idempotency_key).to eq("first_workout_started:#{user.id}:#{session_id}")
      end

      it "does not track first_workout_started when the user already completed a workout" do
        user.workout_sessions.create!(status: "completed", completion_status: "completed", completed_at: 1.day.ago, duration_minutes: 30)

        authed_post "/api/v1/workout_sessions/start", as: user, params: { source: "web" }

        expect(response).to have_http_status(:created)
        expect(UserEvent.where(user: user, event_name: "first_workout_started").count).to eq(0)
      end
    end

    describe "POST /api/v1/workout_sessions/:id/cancel" do
      it "marks the session cancelled and never marks free_workout_used" do
        free_user = create(:user)
        authed_post "/api/v1/workout_sessions/start", as: free_user
        session_id = JSON.parse(response.body)["id"]

        authed_post "/api/v1/workout_sessions/#{session_id}/cancel", as: free_user

        expect(response).to have_http_status(:ok)
        expect(WorkoutSession.find(session_id).status).to eq("cancelled")
        expect(free_user.reload.free_workout_used?).to eq(false)
      end
    end

    describe "full start -> exercise_sessions -> sets -> finish flow" do
      it "records sets incrementally and computes completion server-side on finish" do
        authed_post "/api/v1/workout_sessions/start", as: user, params: { source: "web" }
        session_id = JSON.parse(response.body)["id"]

        authed_post "/api/v1/workout_sessions/#{session_id}/exercise_sessions", as: user,
          params: { exercise_id: exercise.id, planned_sets: 2 }
        exercise_session_id = JSON.parse(response.body)["id"]

        authed_post "/api/v1/workout_sessions/#{session_id}/exercise_sessions/#{exercise_session_id}/sets", as: user,
          params: { set_number: 1, weight_kg: 12, reps: 10, is_warmup: false }
        expect(response).to have_http_status(:created)

        authed_post "/api/v1/workout_sessions/#{session_id}/exercise_sessions/#{exercise_session_id}/sets", as: user,
          params: { set_number: 2, weight_kg: 12, reps: 9, is_warmup: false }
        expect(response).to have_http_status(:created)

        authed_patch "/api/v1/workout_sessions/#{session_id}/exercise_sessions/#{exercise_session_id}", as: user,
          params: { status: "completed" }
        expect(response).to have_http_status(:ok)

        expect(FitnessIntelligence).to receive(:recalculate_safely)
        authed_post "/api/v1/workout_sessions/#{session_id}/finish", as: user, params: { fatigue_level: 3 }

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["completion_status"]).to eq("completed")
        expect(body["completed_sets_count"]).to eq(2)
        expect(body["planned_sets_count"]).to eq(2)
        expect(body["exercise_logs"].first["weight_by_set"].map(&:to_f)).to eq([ 12.0, 12.0 ])
        expect(body["exercise_logs"].first["reps"]).to eq([ 10, 9 ])
      end

      it "tracks first_workout_completed (V1 push event) on the first completed session" do
        authed_post "/api/v1/workout_sessions/start", as: user, params: { source: "web" }
        session_id = JSON.parse(response.body)["id"]

        authed_post "/api/v1/workout_sessions/#{session_id}/finish", as: user, params: { fatigue_level: 3 }

        expect(response).to have_http_status(:ok)
        event = UserEvent.find_by(user: user, event_name: "first_workout_completed")
        expect(event).to be_present
        expect(event.idempotency_key).to eq("first_workout_completed:#{user.id}:#{session_id}")
        # The duplicate activation_first_workout_completed event was removed in V1.
        expect(UserEvent.exists?(user: user, event_name: "activation_first_workout_completed")).to be(false)
        # Funnel: the completion is marked eligible for the push.
        expect(UserEvent.exists?(user: user, event_name: "push_event_eligible")).to be(true)
      end

      it "posting the same set_number twice updates instead of duplicating (retry safety)" do
        authed_post "/api/v1/workout_sessions/start", as: user
        session_id = JSON.parse(response.body)["id"]
        authed_post "/api/v1/workout_sessions/#{session_id}/exercise_sessions", as: user, params: { exercise_id: exercise.id }
        exercise_session_id = JSON.parse(response.body)["id"]

        authed_post "/api/v1/workout_sessions/#{session_id}/exercise_sessions/#{exercise_session_id}/sets", as: user,
          params: { set_number: 1, weight_kg: 10, reps: 12, is_warmup: false }
        authed_post "/api/v1/workout_sessions/#{session_id}/exercise_sessions/#{exercise_session_id}/sets", as: user,
          params: { set_number: 1, weight_kg: 15, reps: 8, is_warmup: false }

        expect(ExerciseSession.find(exercise_session_id).exercise_sets.count).to eq(1)
        expect(ExerciseSession.find(exercise_session_id).exercise_sets.first.weight_kg).to eq(15.0)
      end
    end

    describe "GET /api/v1/workout_sessions/:id" do
      it "returns an execution snapshot reflecting recorded sets" do
        authed_post "/api/v1/workout_sessions/start", as: user
        session_id = JSON.parse(response.body)["id"]
        authed_post "/api/v1/workout_sessions/#{session_id}/exercise_sessions", as: user,
          params: { exercise_id: exercise.id, planned_sets: 3 }
        exercise_session_id = JSON.parse(response.body)["id"]
        authed_post "/api/v1/workout_sessions/#{session_id}/exercise_sessions/#{exercise_session_id}/sets", as: user,
          params: { set_number: 1, weight_kg: 10, reps: 10, is_warmup: false }

        authed_get "/api/v1/workout_sessions/#{session_id}", as: user

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["is_current_session_in_progress"]).to eq(true)
        exercise_json = body["exercise_sessions"].first
        expect(exercise_json["completed_sets_count"]).to eq(1)
        expect(exercise_json["total_sets_count"]).to eq(3)
        expect(exercise_json["current_weight_kg"]).to eq("10.0")
      end
    end
  end
end
