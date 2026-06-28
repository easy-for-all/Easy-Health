require "rails_helper"

RSpec.describe "Api::V1::Coach::Recommendations", type: :request do
  let(:user)    { create(:user) }
  let(:other)   { create(:user) }
  let(:headers) { { "Content-Type" => "application/json" } }

  let!(:exercise) do
    Exercise.create!(
      name:           "Supino Reto",
      muscle_group:   "chest",
      exercise_type:  "musculacao",
      equipment_type: "barbell",
      difficulty:     "intermediate"
    )
  end

  def create_recommendation(owner: user, status: "pending", overrides: {})
    CoachRecommendation.create!(
      {
        user:                owner,
        exercise:            exercise,
        recommendation_type: "weight_progression",
        status:              status,
        title:               "Progressão sugerida",
        message:             "Aumente de 15kg para 17.5kg",
        exercise_name:       exercise.name,
        current_value:       15.0,
        recommended_value:   17.5,
        unit:                "kg",
        confidence:          0.85,
        reasons:             [ "Carga estável", "Séries concluídas" ],
        accepted_at:         status == "accepted" ? Time.current : nil,
        dismissed_at:        status == "dismissed" ? Time.current : nil
      }.merge(overrides)
    )
  end

  describe "GET /api/v1/coach/recommendations/current" do
    context "when authenticated" do
      before { sign_in user }

      it "returns null when no pending recommendation exists" do
        get "/api/v1/coach/recommendations/current", headers: headers
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["recommendation"]).to be_nil
      end

      it "returns the pending recommendation for the current user" do
        rec = create_recommendation
        get "/api/v1/coach/recommendations/current", headers: headers
        body = JSON.parse(response.body)
        expect(response).to have_http_status(:ok)
        expect(body["recommendation"]["id"]).to eq(rec.id)
        expect(body["recommendation"]["type"]).to eq("weight_progression")
        expect(body["recommendation"]["current_value"]).to eq(15.0)
        expect(body["recommendation"]["recommended_value"]).to eq(17.5)
        expect(body["recommendation"]["actions"]).to be_an(Array)
      end

      it "does not return another user's recommendation" do
        create_recommendation(owner: other)
        get "/api/v1/coach/recommendations/current", headers: headers
        body = JSON.parse(response.body)
        expect(body["recommendation"]).to be_nil
      end
    end

    context "when unauthenticated" do
      it "returns 401" do
        get "/api/v1/coach/recommendations/current", headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/coach/recommendations/:id/accept" do
    context "when authenticated" do
      before { sign_in user }

      it "marks the recommendation as accepted" do
        rec = create_recommendation
        post "/api/v1/coach/recommendations/#{rec.id}/accept", headers: headers
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["success"]).to be true
        expect(body["recommendation"]["status"]).to eq("accepted")
        expect(rec.reload.status).to eq("accepted")
        expect(rec.reload.accepted_at).not_to be_nil
      end

      it "returns 404 for another user's recommendation" do
        other_rec = create_recommendation(owner: other)
        post "/api/v1/coach/recommendations/#{other_rec.id}/accept", headers: headers
        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 for an already accepted recommendation" do
        rec = create_recommendation(status: "accepted")
        post "/api/v1/coach/recommendations/#{rec.id}/accept", headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when unauthenticated" do
      it "returns 401" do
        rec = create_recommendation
        post "/api/v1/coach/recommendations/#{rec.id}/accept", headers: headers
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe "POST /api/v1/coach/recommendations/:id/dismiss" do
    context "when authenticated" do
      before { sign_in user }

      it "marks the recommendation as dismissed" do
        rec = create_recommendation
        post "/api/v1/coach/recommendations/#{rec.id}/dismiss", headers: headers
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["success"]).to be true
        expect(rec.reload.status).to eq("dismissed")
        expect(rec.reload.dismissed_at).not_to be_nil
      end

      it "does not alter the exercise load when dismissed" do
        plan = WorkoutPlan.create!(user: user, active: true)
        day  = WorkoutDay.create!(workout_plan: plan, name: "A", day_of_week: 1, position: 0)
        WorkoutDayExercise.create!(workout_day: day, exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 0)

        rec = create_recommendation
        post "/api/v1/coach/recommendations/#{rec.id}/dismiss", headers: headers

        wde = WorkoutDayExercise.last
        expect(wde.planned_weight).to be_nil
      end

      it "returns 404 for another user's recommendation" do
        other_rec = create_recommendation(owner: other)
        post "/api/v1/coach/recommendations/#{other_rec.id}/dismiss", headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
