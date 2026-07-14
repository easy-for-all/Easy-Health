require "rails_helper"

RSpec.describe "Api::V1::QuickWorkouts", type: :request do
  let(:user) { create(:user, paid_plan: true) }
  let(:headers) { { "Content-Type" => "application/json" } }

  before { sign_in user }

  it "selects only gifdotreino exercises for exercise-based quick workouts" do
    valid = Exercise.create!(
      name: "Supino Reto",
      exercise_type: "musculacao",
      muscle_group: "chest",
      gif_url: "/exercise-images/gifdotreino/peitoral/supino-reto.gif"
    )
    invalid = Exercise.create!(
      name: "Supino JPG",
      exercise_type: "musculacao",
      muscle_group: "chest",
      image_url: "/exercise-images/db/Bench/0.jpg"
    )

    post "/api/v1/quick_workouts",
      params: {
        modality: "musculacao",
        duration_minutes: 20,
        location: "academia",
        difficulty: "moderado"
      }.to_json,
      headers: headers

    expect(response).to have_http_status(:created)
    ids = JSON.parse(response.body).dig("day", "exercises").map { |exercise| exercise["exercise_id"] }
    expect(ids).to include(valid.id)
    expect(ids).not_to include(invalid.id)
  end

  it "restricts a strength quick workout to the selected muscle groups" do
    chest = Exercise.create!(
      name: "Supino Reto", exercise_type: "musculacao", muscle_group: "chest",
      gif_url: "/exercise-images/gifdotreino/peitoral/supino-reto.gif"
    )
    back = Exercise.create!(
      name: "Remada Curvada", exercise_type: "musculacao", muscle_group: "back",
      gif_url: "/exercise-images/gifdotreino/costas/remada.gif"
    )

    post "/api/v1/quick_workouts",
      params: {
        modality: "musculacao",
        duration_minutes: 30,
        location: "academia",
        difficulty: "moderado",
        muscle_groups: [ "chest" ]
      }.to_json,
      headers: headers

    expect(response).to have_http_status(:created)
    ids = JSON.parse(response.body).dig("day", "exercises").map { |exercise| exercise["exercise_id"] }
    expect(ids).to include(chest.id)
    expect(ids).not_to include(back.id)
  end
end
