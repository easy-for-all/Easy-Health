require "rails_helper"

RSpec.describe "Api::V1::Auth::Sessions", type: :request do
  let(:user) { create(:user) }

  # The e-mail login was completely dark on the server: the client said it tried
  # (login_started) and the next observable fact was a session existing. A
  # request that never arrived and one the server refused looked identical.
  describe "POST /api/v1/auth/sign_in telemetry" do
    let(:credentials) { { email: user.email, password: user.password } }

    def events(name)
      ProductAnalyticsEvent.where(event_name: name)
    end

    it "records that the request reached the controller, and that it succeeded" do
      post "/api/v1/auth/sign_in", params: credentials, as: :json

      expect(response).to have_http_status(:ok)
      expect(events("email_auth_started").count).to eq(1)
      expect(events("email_auth_started").last.properties).to include(
        "auth_provider" => "email", "auth_intent" => "login"
      )
      expect(events("email_auth_succeeded").count).to eq(1)
      expect(events("email_auth_succeeded").last.user_id).to eq(user.id)
    end

    it "records a refused credential as a category, never as a reason" do
      post "/api/v1/auth/sign_in",
           params: { email: user.email, password: "wrong-password" }, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(events("email_auth_started").count).to eq(1)
      expect(events("email_auth_succeeded").count).to eq(0)
      expect(events("email_auth_failed").last.properties["failure_category"]).to eq("invalid_credentials")
    end

    # An account that does not exist and a wrong password share one category on
    # purpose: splitting them in telemetry is the same enumeration leak the
    # response itself refuses to make.
    it "does not distinguish an unknown e-mail from a wrong password" do
      post "/api/v1/auth/sign_in",
           params: { email: "nobody@example.com", password: "whatever1" }, as: :json

      expect(events("email_auth_failed").last.properties["failure_category"]).to eq("invalid_credentials")
    end

    it "carries the client's attempt id so both halves of the attempt join up" do
      post "/api/v1/auth/sign_in", params: credentials,
           headers: { "X-Auth-Attempt-Id" => "3f6c1d2e-9b0a-4c5d-8e7f-1a2b3c4d5e6f" }, as: :json

      expect(events("email_auth_started").last.properties["auth_attempt_id"])
        .to eq("3f6c1d2e-9b0a-4c5d-8e7f-1a2b3c4d5e6f")
      expect(events("email_auth_succeeded").last.properties["auth_attempt_id"])
        .to eq("3f6c1d2e-9b0a-4c5d-8e7f-1a2b3c4d5e6f")
    end

    it "answers normally when the header is absent — it is never required" do
      post "/api/v1/auth/sign_in", params: credentials, as: :json

      expect(response).to have_http_status(:ok)
      expect(events("email_auth_started").last.properties).not_to have_key("auth_attempt_id")
    end

    it "drops a malformed attempt id instead of keeping it as a dimension" do
      post "/api/v1/auth/sign_in", params: credentials,
           headers: { "X-Auth-Attempt-Id" => "<script>alert(1)</script>" }, as: :json

      expect(response).to have_http_status(:ok)
      expect(events("email_auth_started").last.properties).not_to have_key("auth_attempt_id")
    end

    it "never writes the e-mail or the password into an event" do
      post "/api/v1/auth/sign_in",
           params: { email: user.email, password: "wrong-password" }, as: :json

      payload = ProductAnalyticsEvent.where(event_name: %w[email_auth_started email_auth_failed])
                                     .map { |event| event.properties.to_json }.join
      expect(payload).not_to include(user.email)
      expect(payload).not_to include("wrong-password")
    end
  end

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
