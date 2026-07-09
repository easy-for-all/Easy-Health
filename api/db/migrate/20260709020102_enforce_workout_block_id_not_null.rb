class EnforceWorkoutBlockIdNotNull < ActiveRecord::Migration[8.1]
  # Backfill existing WorkoutDayExercise rows before enforcing the NOT NULL
  # constraint so production deploys do not depend on a manually timed task.
  def up
    backfill_single_blocks
    remaining = select_value("SELECT COUNT(*) FROM workout_day_exercises WHERE workout_block_id IS NULL").to_i
    raise "Cannot enforce workout_block_id NOT NULL: #{remaining} workout_day_exercises still have no block" if remaining.positive?

    change_column_null :workout_day_exercises, :workout_block_id, false
  end

  def down
    change_column_null :workout_day_exercises, :workout_block_id, true
  end

  private

  def backfill_single_blocks
    execute <<~SQL.squish
      WITH rows_to_backfill AS (
        SELECT
          id,
          workout_day_id,
          ROW_NUMBER() OVER (
            PARTITION BY workout_day_id
            ORDER BY COALESCE(order_index, 0), id
          ) AS row_position
        FROM workout_day_exercises
        WHERE workout_block_id IS NULL
      ),
      max_positions AS (
        SELECT workout_day_id, COALESCE(MAX(position), -1) AS max_position
        FROM workout_blocks
        GROUP BY workout_day_id
      ),
      inserted_blocks AS (
        INSERT INTO workout_blocks (
          workout_day_id,
          block_type,
          position,
          rounds,
          created_at,
          updated_at
        )
        SELECT
          rows_to_backfill.workout_day_id,
          'single',
          COALESCE(max_positions.max_position, -1) + rows_to_backfill.row_position,
          1,
          CURRENT_TIMESTAMP,
          CURRENT_TIMESTAMP
        FROM rows_to_backfill
        LEFT JOIN max_positions
          ON max_positions.workout_day_id = rows_to_backfill.workout_day_id
        RETURNING id, workout_day_id, position
      )
      UPDATE workout_day_exercises
      SET
        workout_block_id = inserted_blocks.id,
        position_in_block = 0,
        updated_at = CURRENT_TIMESTAMP
      FROM rows_to_backfill
      LEFT JOIN max_positions
        ON max_positions.workout_day_id = rows_to_backfill.workout_day_id
      JOIN inserted_blocks
        ON inserted_blocks.workout_day_id = rows_to_backfill.workout_day_id
        AND inserted_blocks.position = COALESCE(max_positions.max_position, -1) + rows_to_backfill.row_position
      WHERE workout_day_exercises.id = rows_to_backfill.id
    SQL
  end
end
