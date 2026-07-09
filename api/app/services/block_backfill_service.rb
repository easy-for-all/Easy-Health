# Wraps every pre-existing WorkoutDayExercise in its own "single" WorkoutBlock,
# preserving order_index as the block position. Delegates to the same
# WorkoutDayExercise#ensure_single_block! used for newly created rows, so
# there's a single place that decides how a block gets created. Safe to run
# multiple times: rows that already have a workout_block_id are skipped.
class BlockBackfillService
  def call
    WorkoutDay.find_each do |day|
      # find_each ignores custom .order and iterates by primary key, which
      # would silently scramble block position vs. order_index - a plain
      # .order(...).each is used instead since a single day's exercises are
      # never large enough to need batching.
      day.workout_day_exercises.where(workout_block_id: nil).order(:order_index).each(&:ensure_single_block!)
    end
  end
end
