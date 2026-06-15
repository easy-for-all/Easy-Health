class MakeWorkoutDayOptionalInSessions < ActiveRecord::Migration[7.1]
  def change
    change_column_null :workout_sessions, :workout_day_id, true
  end
end
