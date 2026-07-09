class AddRoundNumberAndBlockToExerciseSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :exercise_sessions, :round_number, :integer, default: 1, null: false
    add_reference :exercise_sessions, :workout_block, null: true, foreign_key: true
  end
end
