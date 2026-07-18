module Make
  module EventContextBuilders
    class FirstWorkoutCompleted < Base
      def as_json
        session = workout_session
        session_id = session&.id || workout_session_id
        completed_at = session&.completed_at || metadata[:completed_at] || metadata[:workout_completed_at]

        compact_hash(
          workout_id: session_id,
          workout_session_id: session_id,
          workout_day_id: session&.workout_day_id || integer_value(:workout_day_id),
          completed_at: iso8601(completed_at),
          duration_minutes: session&.duration_minutes || metadata[:duration_minutes],
          completion_status: session&.completion_status || metadata[:completion_status],
          completion_rate: session&.completion_rate || metadata[:completion_rate]
        )
      end
    end
  end
end
