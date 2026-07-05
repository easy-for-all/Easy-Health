require "rails_helper"

RSpec.describe "Api::V1::WorkoutExerciseSessions", type: :request do
  let(:user) { create(:user, paid_plan: true) }
  let(:exercise) do
    Exercise.create!(
      name: "Rosca com Halteres",
      exercise_type: "musculacao",
      muscle_group: "biceps",
      gif_url: "/exercise-images/gifdotreino/biceps/rosca-com-halteres.gif"
    )
  end
  let(:cardio_exercise) do
    Exercise.create!(
      name: "Corrida",
      exercise_type: "corrida",
      gif_url: "/exercise-images/gifdotreino/cardio/corrida.gif"
    )
  end
  let(:workout_session) { user.workout_sessions.create!(status: "in_progress") }

  def authed(verb, path, params: {})
    sign_in user
    public_send(verb, path, params: params)
  end

  describe "POST /api/v1/workout_sessions/:workout_session_id/exercise_sessions" do
    it "creates a strength exercise_session with defaults inferred from the exercise" do
      authed :post, "/api/v1/workout_sessions/#{workout_session.id}/exercise_sessions",
        params: { exercise_id: exercise.id, planned_sets: 3 }

      expect(response).to have_http_status(:created)
      created = workout_session.exercise_sessions.last
      expect(created.exercise_kind).to eq("strength")
      expect(created.planned_sets).to eq(3)
    end

    it "infers exercise_kind: cardio from a linked workout_day_exercise" do
      plan = user.workout_plans.create!(active: true)
      day = plan.workout_days.create!(name: "Cardio", day_of_week: 0)
      wde = day.workout_day_exercises.create!(exercise: cardio_exercise, order_index: 0, duration_minutes: 20, rest_seconds: 0)

      authed :post, "/api/v1/workout_sessions/#{workout_session.id}/exercise_sessions",
        params: { exercise_id: cardio_exercise.id, workout_day_exercise_id: wde.id }

      expect(response).to have_http_status(:created)
      expect(workout_session.exercise_sessions.last.exercise_kind).to eq("cardio")
    end

    it "returns 404 for a workout_session belonging to another user" do
      other_session = create(:user).workout_sessions.create!(status: "in_progress")

      authed :post, "/api/v1/workout_sessions/#{other_session.id}/exercise_sessions", params: { exercise_id: exercise.id }

      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 when the exercise does not exist" do
      authed :post, "/api/v1/workout_sessions/#{workout_session.id}/exercise_sessions", params: { exercise_id: -1 }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/workout_sessions/:workout_session_id/exercise_sessions/:id" do
    it "marks the exercise_session completed and stamps completed_at" do
      exercise_session = workout_session.exercise_sessions.create!(exercise: exercise, order_index: 0, exercise_kind: "strength", started_at: Time.current)

      authed :patch, "/api/v1/workout_sessions/#{workout_session.id}/exercise_sessions/#{exercise_session.id}", params: { status: "completed" }

      expect(response).to have_http_status(:ok)
      expect(exercise_session.reload.status).to eq("completed")
      expect(exercise_session.completed_at).to be_present
    end
  end
end
