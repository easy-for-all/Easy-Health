require "rails_helper"

RSpec.describe WorkoutDayExercise, type: :model do
  let(:user) { create(:user) }
  let(:plan) { user.workout_plans.create!(active: true) }
  let(:day) { plan.workout_days.create!(name: "Treino A", day_of_week: 1) }
  let(:exercise) { Exercise.create!(name: "Supino Reto", exercise_type: "musculacao", muscle_group: "chest") }

  describe "#ensure_single_block!" do
    it "auto-creates a single block when none is assigned" do
      wde = day.workout_day_exercises.create!(exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 0)

      expect(wde.workout_block).to be_present
      expect(wde.workout_block.block_type).to eq("single")
      expect(wde.position_in_block).to eq(0)
    end

    it "does not overwrite a block explicitly assigned at creation" do
      block = day.workout_blocks.create!(block_type: "superset", position: 0, rounds: 3)
      wde = day.workout_day_exercises.create!(
        exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 0,
        workout_block: block, position_in_block: 1
      )

      expect(wde.workout_block_id).to eq(block.id)
      expect(wde.position_in_block).to eq(1)
    end

    it "assigns each new single-block exercise the next block position within the day" do
      first = day.workout_day_exercises.create!(exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 0)
      other_exercise = Exercise.create!(name: "Remada Baixa", exercise_type: "musculacao", muscle_group: "back")
      second = day.workout_day_exercises.create!(exercise: other_exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 1)

      expect(second.workout_block.position).to be > first.workout_block.position
    end
  end
end
