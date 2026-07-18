module Make
  module EventContextBuilders
    class Base
      def initialize(event)
        @event = event
      end

      def as_json
        {}
      end

      private

      attr_reader :event

      def user
        event.user
      end

      def metadata
        @metadata ||= RelationshipEventTracker.sanitize_metadata(event.metadata || {}).with_indifferent_access
      end

      def compact_hash(hash)
        hash.compact_blank
      end

      def iso8601(value)
        case value
        when Time, ActiveSupport::TimeWithZone, DateTime
          value.iso8601
        when Date
          value.iso8601
        else
          value.presence
        end
      end

      def integer_value(*keys)
        keys.each do |key|
          value = metadata[key]
          integer = Integer(value, exception: false)
          return integer if integer&.positive?
        end
        nil
      end

      def workout_plan_id
        integer_value(:workout_plan_id, :plan_id, :workout_id)
      end

      def workout_session_id
        integer_value(:workout_session_id, :session_id, :workout_id)
      end

      def workout_plan
        id = workout_plan_id
        return user.workout_plans.find_by(id: id) if id

        user.workout_plans.order(:created_at).first
      end

      def workout_session
        id = workout_session_id
        return user.workout_sessions.find_by(id: id) if id

        user.workout_sessions.order(:completed_at).first
      end

      def minutes_since(time)
        started_at = parse_time(time)
        return unless started_at && event.occurred_at

        ((event.occurred_at - started_at) / 60).floor
      end

      def parse_time(value)
        case value
        when Time, ActiveSupport::TimeWithZone, DateTime
          value
        when String
          Time.zone.parse(value)
        end
      rescue ArgumentError
        nil
      end
    end
  end
end
