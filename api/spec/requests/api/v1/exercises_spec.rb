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
      gif_url:        "/exercise-images/triceps_corda.gif",
    )
  end

  let!(:triceps_bench) do
    Exercise.create!(
      name:           "Tríceps Banco",
      muscle_group:   "triceps",
      exercise_type:  "musculacao",
      equipment_type: "bodyweight",
      difficulty:     "beginner",
      gif_url:        "/exercise-images/triceps_banco.gif",
    )
  end

  let!(:chest_barbell) do
    Exercise.create!(
      name:           "Supino Reto",
      muscle_group:   "chest",
      exercise_type:  "musculacao",
      equipment_type: "barbell",
      difficulty:     "intermediate",
      gif_url:        "/exercise-images/supino_reto.gif",
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

    it "finds accented exercise when searching without accent (unaccent)" do
      Exercise.create!(
        name:           "Abdução de Ombros",
        muscle_group:   "shoulders",
        exercise_type:  "musculacao",
        equipment_type: "cable",
        difficulty:     "intermediate",
        gif_url:        "/exercise-images/shoulders.gif",
      )
      get "/api/v1/exercises", params: { name: "abducao" }, headers: headers
      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body).map { |e| e["name"] }
      expect(names).to include("Abdução de Ombros")
    end

    it "finds exercise by partial match ignoring case" do
      get "/api/v1/exercises", params: { name: "reto" }, headers: headers
      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body).map { |e| e["name"] }
      expect(names).to include("Supino Reto")
    end

    it "returns empty array without error when no exercise matches" do
      get "/api/v1/exercises", params: { name: "xyzabcdef123naoexiste" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it "returns intersection when combining name and muscle_group filters" do
      get "/api/v1/exercises", params: { name: "Supino", muscle_group: "chest" }, headers: headers
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).not_to be_empty
      body.each do |ex|
        expect(ex["muscle_group"]).to eq("chest")
        expect(ex["name"]).to match(/supino/i)
      end
    end

    it "excludes specified ids" do
      get "/api/v1/exercises", params: { muscle_group: "triceps", exclude_ids: triceps_cable.id.to_s }, headers: headers
      ids = JSON.parse(response.body).map { |e| e["id"] }
      expect(ids).not_to include(triceps_cable.id)
    end

    context "with only_favorites=true" do
      it "returns only favorited exercises" do
        UserFavoriteExercise.create!(user: user, exercise: triceps_bench)
        get "/api/v1/exercises", params: { muscle_group: "triceps", only_favorites: "true" }, headers: headers
        ids = JSON.parse(response.body).map { |e| e["id"] }
        expect(ids).to include(triceps_bench.id)
        expect(ids).not_to include(triceps_cable.id)
      end

      it "still excludes exercise when exclude_ids is passed alongside only_favorites" do
        UserFavoriteExercise.create!(user: user, exercise: chest_barbell)
        get "/api/v1/exercises", params: {
          muscle_group:   "chest",
          only_favorites: "true",
          exclude_ids:    chest_barbell.id.to_s,
        }, headers: headers
        ids = JSON.parse(response.body).map { |e| e["id"] }
        expect(ids).not_to include(chest_barbell.id)
      end
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
          gif_url:        "/exercise-images/bike.gif",
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

    context "with lighter intent" do
      let!(:advanced_chest) do
        Exercise.create!(
          name:            "Supino Declinado com Corrente",
          muscle_group:    "chest",
          exercise_type:   "musculacao",
          equipment_type:  "barbell",
          difficulty_level: "advanced",
          gif_url:         "/exercise-images/chest.gif",
        )
      end

      let!(:beginner_chest) do
        Exercise.create!(
          name:            "Supino Máquina",
          muscle_group:    "chest",
          exercise_type:   "musculacao",
          equipment_type:  "machine",
          difficulty_level: "beginner",
          gif_url:         "/exercise-images/chest.gif",
        )
      end

      it "excludes advanced exercises when user requests lighter" do
        post "/api/v1/exercises/intelligent_suggestions",
             params: {
               current_exercise_id: chest_barbell.id,
               user_text:           "mais leve",
             }.to_json,
             headers: headers

        ids = JSON.parse(response.body)["exercises"].map { |e| e["id"] }
        expect(ids).not_to include(advanced_chest.id)
        expect(ids).to include(beginner_chest.id)
      end
    end

    context "with heavier intent" do
      let!(:beginner_triceps) do
        Exercise.create!(
          name:            "Tríceps Francês",
          muscle_group:    "triceps",
          exercise_type:   "musculacao",
          equipment_type:  "dumbbell",
          difficulty_level: "beginner",
          gif_url:         "/exercise-images/triceps.gif",
        )
      end

      let!(:advanced_triceps) do
        Exercise.create!(
          name:            "Tríceps Coice Unilateral",
          muscle_group:    "triceps",
          exercise_type:   "musculacao",
          equipment_type:  "dumbbell",
          difficulty_level: "advanced",
          gif_url:         "/exercise-images/triceps.gif",
        )
      end

      it "excludes beginner exercises when user requests heavier" do
        post "/api/v1/exercises/intelligent_suggestions",
             params: {
               current_exercise_id: triceps_cable.id,
               user_text:           "mais pesado",
             }.to_json,
             headers: headers

        ids = JSON.parse(response.body)["exercises"].map { |e| e["id"] }
        expect(ids).not_to include(beginner_triceps.id)
        expect(ids).to include(advanced_triceps.id)
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
