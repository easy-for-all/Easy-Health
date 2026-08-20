require "rails_helper"

RSpec.describe UserFavoriteExercise, type: :model do
  let(:user) { create(:user) }
  let(:exercise) do
    Exercise.create!(
      name: "Tríceps banco",
      exercise_type: "musculacao",
      muscle_group: "triceps",
      gif_url: "/exercise-images/gifdotreino/triceps/triceps-banco.gif"
    )
  end

  it "enqueues recalibration with the added source" do
    favorite = described_class.new(user: user, exercise: exercise)

    expect(RecalibrateFitnessProfileJob).to receive(:perform_later)
      .with(user.id, source: "favorite_exercise_added")

    favorite.send(:trigger_fitness_recalibration_after_create)
  end

  it "enqueues recalibration with the removed source" do
    favorite = described_class.new(user: user, exercise: exercise)

    expect(RecalibrateFitnessProfileJob).to receive(:perform_later)
      .with(user.id, source: "favorite_exercise_removed")

    favorite.send(:trigger_fitness_recalibration_after_destroy)
  end
end
