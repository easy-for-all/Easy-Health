module Make
  module EventContextBuilders
    # Anchor of the activation journey. Everything here already lives in the
    # metadata written by WorkoutPlansController#track_activation_workout_created;
    # the builder only lifts it to the flat `context` shape Make reads, falling
    # back to the plan record when the metadata is missing (backfilled rows).
    class ActivationWorkoutCreated < Base
      def as_json
        plan = workout_plan
        plan_id = plan&.id || workout_plan_id
        workout = metadata[:workout].presence || {}
        activation = metadata[:activation].presence || {}

        compact_hash(
          workout_id: plan_id,
          plan_id: plan_id,
          workout_name: workout[:name],
          exercises_count: workout[:exercises_count],
          estimated_duration_minutes: workout[:estimated_duration_minutes],
          muscle_groups: workout[:muscle_groups],
          onboarding_variant: activation[:onboarding_variant],
          workout_created_at: iso8601(plan&.created_at || metadata[:workout_created_at])
        )
      end
    end
  end
end
