module Make
  module EventContextBuilders
    class Inactivity < Base
      def as_json
        last_workout_at = metadata[:last_workout_at] || user.workout_sessions.maximum(:completed_at)
        parsed_last_workout_at = parse_time(last_workout_at)
        days = metadata[:days_since_last_workout] || days_since(parsed_last_workout_at)

        compact_hash(
          reference_at: iso8601(event.occurred_at),
          last_workout_at: iso8601(last_workout_at),
          days_since_last_workout: days
        )
      end

      private

      def days_since(time)
        return unless time

        (Date.current - time.to_date).to_i
      end
    end
  end
end
