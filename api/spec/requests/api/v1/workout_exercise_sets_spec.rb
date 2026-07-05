require "rails_helper"

RSpec.describe "Api::V1::WorkoutExerciseSets", type: :request do
  let(:user) { create(:user, paid_plan: true) }
  let(:exercise) { Exercise.create!(name: "Rosca com Halteres", exercise_type: "musculacao", muscle_group: "biceps") }
  let(:workout_session) { user.workout_sessions.create!(status: "in_progress") }
  let(:exercise_session) { workout_session.exercise_sessions.create!(exercise: exercise, order_index: 0, exercise_kind: "strength", started_at: Time.current) }

  def authed(verb, path, params: {})
    sign_in user
    public_send(verb, path, params: params)
  end

  describe "POST /api/v1/workout_sessions/:workout_session_id/exercise_sessions/:exercise_session_id/sets" do
    it "records a set immediately with completed_at" do
      authed :post, "/api/v1/workout_sessions/#{workout_session.id}/exercise_sessions/#{exercise_session.id}/sets",
        params: { set_number: 1, weight_kg: 15, reps: 10, is_warmup: false }

      expect(response).to have_http_status(:created)
      set = exercise_session.exercise_sets.sole
      expect(set.weight_kg).to eq(15.0)
      expect(set.reps).to eq(10)
      expect(set.is_warmup).to eq(false)
      expect(set.completed_at).to be_present
    end

    it "upserts the same set_number instead of creating a duplicate row (network retry safety)" do
      params = { set_number: 1, weight_kg: 10, reps: 12, is_warmup: false }
      authed :post, "/api/v1/workout_sessions/#{workout_session.id}/exercise_sessions/#{exercise_session.id}/sets", params: params
      authed :post, "/api/v1/workout_sessions/#{workout_session.id}/exercise_sessions/#{exercise_session.id}/sets", params: params

      expect(exercise_session.exercise_sets.count).to eq(1)
    end

    it "returns 404 for an exercise_session belonging to another user" do
      other_session = create(:user).workout_sessions.create!(status: "in_progress")
      other_exercise_session = other_session.exercise_sessions.create!(exercise: exercise, order_index: 0, exercise_kind: "strength", started_at: Time.current)

      authed :post, "/api/v1/workout_sessions/#{workout_session.id}/exercise_sessions/#{other_exercise_session.id}/sets",
        params: { set_number: 1, weight_kg: 10, reps: 10, is_warmup: false }

      expect(response).to have_http_status(:not_found)
    end
  end
end
