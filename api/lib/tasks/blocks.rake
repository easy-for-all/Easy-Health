namespace :blocks do
  desc "Backfill workout_blocks for pre-existing WorkoutDayExercise rows, each wrapped in its own 'single' block. Idempotent, safe to re-run."
  task backfill_single_blocks: :environment do
    before = WorkoutDayExercise.where(workout_block_id: nil).count
    BlockBackfillService.new.call
    after = WorkoutDayExercise.where(workout_block_id: nil).count

    puts "#{before - after} WorkoutDayExercise rows backfilled into single blocks, #{after} still without a block"
  end

  desc "Fail unless every WorkoutDayExercise has a workout_block_id."
  task assert_no_null_workout_blocks: :environment do
    missing = WorkoutDayExercise.where(workout_block_id: nil).count
    abort "#{missing} WorkoutDayExercise rows still do not have a workout_block_id" if missing.positive?

    puts "All WorkoutDayExercise rows have a workout_block_id"
  end
end
