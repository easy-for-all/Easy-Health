require "rails_helper"

RSpec.describe BlockBackfillService do
  let(:user) { create(:user) }
  let(:plan) { user.workout_plans.create!(active: true) }
  let(:day) { plan.workout_days.create!(name: "Treino A", day_of_week: 1) }

  def create_legacy_exercise(name, order_index)
    exercise = Exercise.create!(name: name, exercise_type: "musculacao", muscle_group: "chest")
    wde = day.workout_day_exercises.create!(exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: order_index)
    # Simulate data that existed before this feature shipped: no block yet,
    # bypassing the after_create callback the same way a pre-migration row would.
    wde.update_columns(workout_block_id: nil, position_in_block: nil)
    wde
  end

  it "wraps each pre-existing WorkoutDayExercise in its own single block, preserving order" do
    third = create_legacy_exercise("Exercicio C", 2)
    first = create_legacy_exercise("Exercicio A", 0)
    second = create_legacy_exercise("Exercicio B", 1)

    described_class.new.call

    [first, second, third].each(&:reload)
    expect(first.workout_block.block_type).to eq("single")
    expect(second.workout_block.block_type).to eq("single")
    expect(third.workout_block.block_type).to eq("single")

    expect(first.workout_block_id).not_to eq(second.workout_block_id)
    expect(second.workout_block_id).not_to eq(third.workout_block_id)

    expect(first.workout_block.position).to be < second.workout_block.position
    expect(second.workout_block.position).to be < third.workout_block.position
  end

  it "is idempotent when run twice" do
    create_legacy_exercise("Exercicio A", 0)

    described_class.new.call
    expect { described_class.new.call }.not_to change { WorkoutBlock.count }
    expect(WorkoutDayExercise.where(workout_block_id: nil).count).to eq(0)
  end
end
