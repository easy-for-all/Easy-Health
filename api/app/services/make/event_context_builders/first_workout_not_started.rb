module Make
  module EventContextBuilders
    # Context for first_workout_not_started_2h / _24h. Anchor is the first plan
    # creation; the emitting job stamps first_workout_created_at in metadata.
    class FirstWorkoutNotStarted < Base
      def as_json
        created_at = parse_time(metadata[:first_workout_created_at]) || workout_plan&.created_at

        compact_hash(
          first_workout_created_at: iso8601(created_at),
          hours_since_creation: hours_since(created_at),
          total_workouts_completed: user.workout_sessions.count
        )
      end

      private

      def hours_since(time)
        started_at = parse_time(time)
        return unless started_at && event.occurred_at

        ((event.occurred_at - started_at) / 3600).floor
      end
    end
  end
end
