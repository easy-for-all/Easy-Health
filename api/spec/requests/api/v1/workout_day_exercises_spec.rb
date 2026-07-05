require "rails_helper"

RSpec.describe "Api::V1::WorkoutDayExercises", type: :request do
  let(:user) { create(:user, paid_plan: true) }
  let(:headers) { { "Content-Type" => "application/json" } }
  let(:plan) { user.workout_plans.create!(active: true) }
  let(:day) { plan.workout_days.create!(name: "Treino A", day_of_week: 1) }
  let(:current_exercise) do
    Exercise.create!(
      name: "Supino Reto",
      exercise_type: "musculacao",
      muscle_group: "chest",
      gif_url: "/exercise-images/gifdotreino/peitoral/supino-reto.gif"
    )
  end
  let(:invalid_exercise) do
    Exercise.create!(
      name: "Supino JPG",
      exercise_type: "musculacao",
      muscle_group: "chest",
      image_url: "/exercise-images/db/Barbell_Bench_Press/0.jpg"
    )
  end
  let!(:wde) do
    day.workout_day_exercises.create!(
      exercise: current_exercise,
      sets: 3,
      reps: 10,
      rest_seconds: 60,
      order_index: 0
    )
  end

  before { sign_in user }

  it "rejects swapping to an exercise outside the gifdotreino catalog" do
    post "/api/v1/workout_day_exercises/#{wde.id}/swap",
      params: { replacement_exercise_id: invalid_exercise.id }.to_json,
      headers: headers

    expect(response).to have_http_status(:not_found)
    expect(wde.reload.exercise_id).to eq(current_exercise.id)
  end

  it "rejects adding an exercise outside the gifdotreino catalog" do
    post "/api/v1/workout_days/#{day.id}/exercises",
      params: { exercise_id: invalid_exercise.id }.to_json,
      headers: headers

    expect(response).to have_http_status(:not_found)
    expect(day.workout_day_exercises.reload.pluck(:exercise_id)).to contain_exactly(current_exercise.id)
  end
end
