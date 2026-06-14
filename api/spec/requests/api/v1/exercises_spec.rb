require "rails_helper"

RSpec.describe "Api::V1::Exercises", type: :request do
  let(:user)    { create(:user) }
  let(:headers) { { "Content-Type" => "application/json" } }

  before { sign_in user }

  let!(:triceps_cable) do
    Exercise.create!(
      name:           "Tríceps Corda",
      muscle_group:   "triceps",
      exercise_type:  "musculacao",
      equipment_type: "cable",
      difficulty:     "intermediate",
    )
  end

  let!(:triceps_bench) do
    Exercise.create!(
      name:           "Tríceps Banco",
      muscle_group:   "triceps",
      exercise_type:  "musculacao",
      equipment_type: "bodyweight",
      difficulty:     "beginner",
    )
  end

  let!(:chest_barbell) do
    Exercise.create!(
      name:           "Supino Reto",
      muscle_group:   "chest",
      exercise_type:  "musculacao",
      equipment_type: "barbell",
      difficulty:     "intermediate",
    )
  end

  describe "GET /api/v1/exercises" do
    it "returns exercises filtered by muscle group" do
      get "/api/v1/exercises", params: { muscle_group: "triceps" }, headers: headers
      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |e| e["id"] }
      expect(ids).to include(triceps_cable.id, triceps_bench.id)
      expect(ids).not_to include(chest_barbell.id)
    end

    it "searches by PT-BR name with accents" do
      get "/api/v1/exercises", params: { name: "Tríceps" }, headers: headers
      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body).map { |e| e["name"] }
      expect(names).to include("Tríceps Corda", "Tríceps Banco")
    end

    it "excludes specified ids" do
      get "/api/v1/exercises", params: { muscle_group: "triceps", exclude_ids: triceps_cable.id.to_s }, headers: headers
      ids = JSON.parse(response.body).map { |e| e["id"] }
      expect(ids).not_to include(triceps_cable.id)
    end
  end

  describe "POST /api/v1/exercises/intelligent_suggestions" do
    it "returns ranked suggestions with reasons" do
      post "/api/v1/exercises/intelligent_suggestions",
           params: {
             current_exercise_id: triceps_cable.id,
             user_text:           "quero algo com halter",
             already_suggested_ids: "",
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["exercises"]).to be_an(Array)
      expect(body["intent"]).to be_a(Hash)
      body["exercises"].each do |ex|
        expect(ex["reason"]).to be_a(String)
        expect(ex["score"]).to be_a(Integer)
      end
    end

    it "returns no_more true when no results and empty exclusions" do
      # Exclude everything
      all_ids = Exercise.where(muscle_group: "triceps").pluck(:id).map(&:to_s).join(",")
      post "/api/v1/exercises/intelligent_suggestions",
           params: {
             current_exercise_id:   triceps_cable.id,
             user_text:             "",
             already_suggested_ids: all_ids,
           }.to_json,
           headers: headers

      body = JSON.parse(response.body)
      expect(body["no_more"]).to be true
    end

    it "returns 422 when current_exercise_id is missing" do
      post "/api/v1/exercises/intelligent_suggestions",
           params: { user_text: "bike" }.to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    context "with cardio intent (bike)" do
      let!(:bike_exercise) do
        Exercise.create!(
          name:           "Bike Ergométrica",
          muscle_group:   "legs",
          exercise_type:  "cardio",
          equipment_type: "cardio",
          difficulty:     "beginner",
        )
      end

      it "returns cardio exercises when user requests bike" do
        post "/api/v1/exercises/intelligent_suggestions",
             params: {
               current_exercise_id: triceps_cable.id,
               user_text:           "quero bike",
             }.to_json,
             headers: headers

        body = JSON.parse(response.body)
        expect(body["intent"]["intent_type"]).to eq("replace_with_cardio")
        ids = body["exercises"].map { |e| e["id"] }
        expect(ids).to include(bike_exercise.id)
      end
    end
  end

  describe "POST /api/v1/exercises/:id/suggestion_feedback" do
    it "creates a suggestion_shown log" do
      expect do
        post "/api/v1/exercises/#{triceps_bench.id}/suggestion_feedback",
             params: {
               event_type:          "suggestion_shown",
               current_exercise_id: triceps_cable.id,
               intent_text:         "algo com halter",
             }.to_json,
             headers: headers
      end.to change(ExerciseSuggestionLog, :count).by(1)

      expect(response).to have_http_status(:created)
      log = ExerciseSuggestionLog.last
      expect(log.event_type).to eq("suggestion_shown")
      expect(log.user).to eq(user)
    end

    it "creates a suggestion_accepted log and sets accepted=true" do
      post "/api/v1/exercises/#{triceps_bench.id}/suggestion_feedback",
           params: {
             event_type:          "suggestion_accepted",
             current_exercise_id: triceps_cable.id,
           }.to_json,
           headers: headers

      expect(response).to have_http_status(:created)
      expect(ExerciseSuggestionLog.last.accepted).to be true
    end

    it "returns 422 for invalid event_type" do
      post "/api/v1/exercises/#{triceps_bench.id}/suggestion_feedback",
           params: { event_type: "invalid_event" }.to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
