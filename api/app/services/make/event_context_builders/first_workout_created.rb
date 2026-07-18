module Make
  module EventContextBuilders
    class FirstWorkoutCreated < Base
      def as_json
        plan = workout_plan
        plan_id = plan&.id || workout_plan_id
        created_at = plan&.created_at || metadata[:workout_created_at] || metadata[:workout_plan_created_at]

        compact_hash(
          workout_id: plan_id,
          plan_id: plan_id,
          workout_created_at: iso8601(created_at)
        )
      end
    end
  end
end
