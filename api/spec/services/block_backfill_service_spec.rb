require "rails_helper"

# NOTE: workout_day_exercises.workout_block_id is NOT NULL at the DB level
# (enforced by the EnforceWorkoutBlockIdNotNull migration, which now performs
# its own backfill inline before adding the constraint). That means a row
# with a null workout_block_id can no longer exist in this schema version -
# every WorkoutDayExercise is guaranteed to already have a block via
# WorkoutDayExercise#ensure_single_block!. BlockBackfillService is kept as a
# harmless, idempotent no-op for any data that somehow still needs it (e.g.
# restoring from an old backup taken before the migration), rather than
# deleted, since it's cheap to keep and the migration itself documents the
# same intent.
RSpec.describe BlockBackfillService do
  let(:user) { create(:user) }
  let(:plan) { user.workout_plans.create!(active: true) }
  let(:day) { plan.workout_days.create!(name: "Treino A", day_of_week: 1) }

  it "is a no-op when every WorkoutDayExercise already has a block" do
    exercise = Exercise.create!(name: "Supino", exercise_type: "musculacao", muscle_group: "chest")
    wde = day.workout_day_exercises.create!(exercise: exercise, sets: 3, reps: 10, rest_seconds: 60, order_index: 0)
    original_block_id = wde.workout_block_id

    expect { described_class.new.call }.not_to change { WorkoutBlock.count }
    expect(wde.reload.workout_block_id).to eq(original_block_id)
  end

  it "does not raise when there is nothing to backfill" do
    expect { described_class.new.call }.not_to raise_error
  end
end
