require "rails_helper"

RSpec.describe "Api::V1::Auth::Sessions", type: :request do
  let(:user) { create(:user) }

  describe "GET /api/v1/auth/me" do
    it "returns semantic completed workout fields from real completed sessions" do
      sign_in user

      user.workout_sessions.create!(
        status: "completed",
        completion_status: "completed",
        completed_at: 3.days.ago,
        duration_minutes: 35,
        exercise_logs: []
      )
      user.workout_sessions.create!(
        status: "completed",
        completion_status: "completed",
        completed_at: 1.day.ago,
        duration_minutes: 42,
        exercise_logs: []
      )
      user.workout_sessions.create!(
        status: "completed",
        completion_status: "completed_partial",
        completed_at: Time.current,
        duration_minutes: 20,
        exercise_logs: []
      )
      user.workout_sessions.create!(
        status: "cancelled",
        completion_status: "abandoned",
        duration_minutes: 5,
        exercise_logs: []
      )

      get "/api/v1/auth/me"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["completed_workouts_count"]).to eq(2)
      expect(response.parsed_body["has_completed_workout"]).to be(true)
    end

    it "does not mark a new user as having completed a workout" do
      sign_in user

      get "/api/v1/auth/me"

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["completed_workouts_count"]).to eq(0)
      expect(response.parsed_body["has_completed_workout"]).to be(false)
    end
  end
end
