module Make
  class EventPayloadSerializer
    SOURCE = "easyhealth_backend".freeze

    class IncompleteEventError < StandardError; end

    REQUIRED_CONTEXT = {
      "first_workout_not_started_2h" => %i[first_workout_created_at],
      "first_workout_not_started_24h" => %i[first_workout_created_at],
      "workout_created_not_started" => %i[workout_id],
      "first_workout_created" => %i[plan_id],
      "first_workout_completed" => %i[workout_session_id],
      "plan_created_but_not_used" => %i[plan_id],
      "user_inactive_3_days" => %i[last_workout_at],
      "user_inactive_7_days" => %i[last_workout_at],
      "user_inactive_15_days" => %i[last_workout_at]
    }.freeze

    def initialize(event:, schema_version: MakeWebhookEligibility.event_schema_version, delivery_channels: nil)
      @event = event
      @schema_version = Integer(schema_version)
      @delivery_channels = delivery_channels
    end

    def as_json
      case schema_version
      when 1
        schema_one_payload
      when 2
        schema_two_payload
      else
        raise ArgumentError, "MAKE_EVENT_SCHEMA_VERSION must be 1 or 2"
      end
    end

    private

    attr_reader :event, :schema_version, :delivery_channels

    def schema_one_payload
      {
        schema_version: 1,
        event_id: event.id,
        event_name: event.event_name,
        occurred_at: event.occurred_at&.iso8601,
        source: event.source,
        environment: Rails.env,
        user: user_payload,
        segments: segments_payload,
        subscription: subscription_payload,
        engagement: engagement_payload,
        metadata: sanitized_metadata
      }
    end

    def schema_two_payload
      context = Make::EventContextBuilders.build(event)
      payload = {
        schema_version: 2,
        event_id: event.id,
        event_name: event.event_name,
        occurred_at: event.occurred_at&.iso8601,
        source: SOURCE,
        environment: Rails.env,
        delivery: {
          channels: resolved_channels
        },
        user: user_payload,
        segments: segments_payload,
        subscription: subscription_payload,
        engagement: engagement_payload,
        context: context,
        metadata: schema_two_metadata
      }

      pb = push_block
      payload[:push] = pb if pb

      validate_context!(payload)
      payload
    end

    # Technical push descriptor from communication_events.yml. Copy (title/body)
    # is chosen by Make from event_name and is NEVER included here. campaign_key
    # equals event_name (V1). Absent for email-only events.
    def push_block
      notification_type = CommunicationEvents.notification_type_for(event.event_name)
      return nil if notification_type.blank?

      {
        notification_type: notification_type,
        route: CommunicationEvents.route_for(event.event_name),
        campaign_key: event.event_name
      }
    rescue CommunicationEvents::UnknownEventError
      nil
    end

    def user
      event.user
    end

    def user_payload
      payload = {
        id: user.id,
        timezone: user.time_zone.presence || "America/Sao_Paulo",
        locale: "pt-BR"
      }
      return payload if MakeWebhookEligibility.payload_mode == "minimal"

      payload.merge(
        email: user.email,
        name: user.name
      )
    end

    def segments_payload
      user.user_segments.active.order(:segment_name).pluck(:segment_name)
    rescue ActiveRecord::StatementInvalid, NoMethodError
      []
    end

    def subscription_payload
      subscription = user.subscription
      {
        status: subscription&.status || "none",
        trial_ends_at: subscription&.trial_end&.iso8601 || user.trial_ends_at&.iso8601,
        plan: subscription&.plan_name || "none"
      }
    end

    def engagement_payload
      last_workout_at = user.workout_sessions.maximum(:completed_at)
      {
        created_at: user.created_at.iso8601,
        last_sign_in_at: nil,
        last_workout_at: last_workout_at&.iso8601,
        total_workouts_created: user.workout_plans.count,
        total_workouts_completed: user.workout_sessions.count,
        days_since_last_workout: last_workout_at ? (Date.current - last_workout_at.to_date).to_i : nil
      }
    end

    def sanitized_metadata
      RelationshipEventTracker.sanitize_metadata(event.metadata || {})
    end

    def schema_two_metadata
      metadata = sanitized_metadata.deep_dup
      source = metadata.delete("source")
      metadata["trigger_source"] ||= source if source.present?
      if metadata["trigger_source"].blank? && event.source.present? && event.source != SOURCE
        metadata["trigger_source"] = event.source
      end
      metadata
    end

    def resolved_channels
      if delivery_channels.nil?
        CommunicationEvents.channels_for(event.event_name)
      else
        CommunicationEvents.validate_event_name!(event.event_name)
        CommunicationEvents.validate_channels!(delivery_channels)
      end
    end

    def validate_context!(payload)
      required = REQUIRED_CONTEXT.fetch(event.event_name.to_s, [])
      return if required.empty?

      context = payload[:context].with_indifferent_access
      missing = required.select { |field| context[field].blank? }
      return if missing.empty?

      raise IncompleteEventError, "missing_required_context event=#{event.event_name} fields=#{missing.join(',')}"
    end
  end
end
