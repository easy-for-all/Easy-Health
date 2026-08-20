require "rails_helper"

RSpec.describe "Api::V1::UserFavoriteExercises", type: :request do
  let(:user) { create(:user) }
  let(:exercise) do
    Exercise.create!(
      name: "Tríceps banco",
      exercise_type: "musculacao",
      muscle_group: "triceps",
      gif_url: "/exercise-images/gifdotreino/triceps/triceps-banco.gif"
    )
  end

  before { sign_in user }

  it "favorites an exercise with the existing response contract and async recalibration" do
    expect(FitnessIntelligence).not_to receive(:recalculate_safely)

    post "/api/v1/exercises/#{exercise.id}/favorite"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("favorited" => true)
    expect(user.reload.favorite_exercises).to contain_exactly(exercise)
  end

  it "unfavorites an exercise with the existing response contract and async recalibration" do
    user.user_favorite_exercises.create!(exercise: exercise)

    expect(FitnessIntelligence).not_to receive(:recalculate_safely)

    delete "/api/v1/exercises/#{exercise.id}/favorite"

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("favorited" => false)
    expect(user.reload.favorite_exercises).to be_empty
  end
end
