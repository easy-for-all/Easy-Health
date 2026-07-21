module Make
  module EventContextBuilders
    class ScheduledWorkoutReminderDue < Base
      def as_json
        activation = metadata[:activation].presence || {}

        compact_hash(
          activation: activation
        )
      end
    end
  end
end
