module Analytics
  # Documented, testable home for push → workout attribution. Generalizes the
  # activation-push case (ActivationPushAttribution delegates here).
  #
  # Rules (see docs/analytics/METRIC_DEFINITIONS.md):
  #   - workout_started_after_push:   first workout STARTED within START_WINDOW
  #     of a push_opened, AND started at/after the push was opened. A workout
  #     started BEFORE the push open is never attributed.
  #   - workout_completed_after_push: workout COMPLETED within COMPLETE_WINDOW,
  #     linked to a delivery already attributed at start.
  #
  # Anti-double-credit:
  #   - One conversion per delivery (a delivery already "converted" is skipped).
  #   - Mirrored product_analytics_events use a deterministic idempotency_key per
  #     delivery, so re-runs (e.g. a push opened twice) never double-attribute.
  class PushAttributionService
    START_WINDOW = 2.hours
    COMPLETE_WINDOW = 24.hours
    # Make-orchestrated pushes (push_dispatches) attribute within 24h of the open.
    DISPATCH_WINDOW = 24.hours

    def self.attribute_start(user, session)
      new(user, session).attribute_start
    end

    def self.attribute_completion(user, session)
      new(user, session).attribute_completion
    end

    def self.attribute_dispatch_start(user, session)
      new(user, session).attribute_dispatch_start
    end

    def self.attribute_dispatch_completion(user, session)
      new(user, session).attribute_dispatch_completion
    end

    def initialize(user, session)
      @user = user
      @session = session
    end

    # Returns the attributed delivery, or nil.
    def attribute_start
      delivery = eligible_opened_delivery
      return nil if delivery.nil?

      delivery.update!(status: "converted", converted_at: Time.current)

      # Legacy relationship event (unchanged behaviour).
      track_relationship_event("workout_started_from_push", delivery, seconds_key: :seconds_to_workout_start)

      # Auditable, idempotent mirror into product_analytics_events.
      ServerEvents.record(
        event_name: "workout_started_after_push",
        user: @user,
        platform: "android",
        occurred_at: workout_started_at,
        idempotency_key: "pushattr:start:#{delivery.id}",
        source: "push_attribution",
        properties: attribution_props(delivery, seconds: seconds_since_open(delivery))
      )
      delivery
    end

    # Returns the attributed delivery, or nil.
    def attribute_completion
      delivery = attributed_delivery
      return nil if delivery.nil?

      track_relationship_event("workout_completed_from_push", delivery)

      ServerEvents.record(
        event_name: "workout_completed_after_push",
        user: @user,
        platform: "android",
        idempotency_key: "pushattr:complete:#{delivery.id}",
        source: "push_attribution",
        properties: attribution_props(delivery)
      )
      delivery
    end

    # --- Family A (Make) attribution on push_dispatches, 24h after open ------

    # A workout STARTED within 24h after a push_dispatch open (opened at/before
    # the start). Anti-double-credit via a deterministic idempotency_key per
    # dispatch (relationship event + product_analytics mirror).
    def attribute_dispatch_start
      dispatch = eligible_opened_dispatch(workout_started_at)
      return nil if dispatch.nil?

      key = "pushattr:start:dispatch:#{dispatch.id}"
      return dispatch if UserEvent.exists?(user: @user, event_name: "workout_started_from_push", idempotency_key: key)

      UserEventService.track(
        user: @user, event_name: "workout_started_from_push", source: "make_push",
        suppress_make_delivery: true, idempotency_key: key, metadata: dispatch_props(dispatch)
      )
      ServerEvents.record(
        event_name: "workout_started_after_push", user: @user, platform: "android",
        occurred_at: workout_started_at, idempotency_key: key, source: "push_attribution",
        properties: dispatch_props(dispatch)
      )
      dispatch
    end

    # A workout COMPLETED within 24h of a dispatch open whose start was already
    # attributed to that dispatch.
    def attribute_dispatch_completion
      dispatch = eligible_opened_dispatch(completed_at)
      return nil if dispatch.nil?
      return nil unless UserEvent.exists?(user: @user, event_name: "workout_started_from_push",
                                          idempotency_key: "pushattr:start:dispatch:#{dispatch.id}")

      key = "pushattr:complete:dispatch:#{dispatch.id}"
      return dispatch if UserEvent.exists?(user: @user, event_name: "workout_completed_from_push", idempotency_key: key)

      UserEventService.track(
        user: @user, event_name: "workout_completed_from_push", source: "make_push",
        suppress_make_delivery: true, idempotency_key: key, metadata: dispatch_props(dispatch)
      )
      ServerEvents.record(
        event_name: "workout_completed_after_push", user: @user, platform: "android",
        idempotency_key: key, source: "push_attribution", properties: dispatch_props(dispatch)
      )
      dispatch
    end

    private

    def eligible_opened_dispatch(at)
      PushDispatch
        .where(user_id: @user.id)
        .where.not(opened_at: nil)
        .where(opened_at: DISPATCH_WINDOW.ago..)
        .where("opened_at <= ?", at)
        .order(opened_at: :desc)
        .first
    end

    def completed_at
      @session.completed_at || Time.current
    end

    def dispatch_props(dispatch)
      {
        notification_type: dispatch.notification_type,
        dispatch_id: dispatch.id,
        campaign_key: dispatch.campaign_key,
        event_name: dispatch.payload_json.is_a?(Hash) ? dispatch.payload_json.dig("data", "event_name") : nil,
        workout_id: @session.workout_day_id
      }.compact
    end

    # Most recent opened, unconverted delivery within START_WINDOW whose open
    # happened AT OR BEFORE the workout start (started after the push open).
    def eligible_opened_delivery
      started_at = workout_started_at
      @user.notification_deliveries
           .where.not(opened_at: nil)
           .where.not(status: "converted") # already attributed — never double-credit
           .where(opened_at: START_WINDOW.ago..)
           .where("opened_at <= ?", started_at)
           .order(opened_at: :desc)
           .first
    end

    def attributed_delivery
      @user.notification_deliveries
           .where(status: "converted")
           .where(converted_at: COMPLETE_WINDOW.ago..)
           .order(converted_at: :desc)
           .first
    end

    # WorkoutSession has no started_at column: the row is created by
    # workout_sessions#start at the moment the workout starts, so created_at is
    # the start time. Fall back to now for unsaved sessions (tests).
    def workout_started_at
      @session.created_at || Time.current
    end

    def seconds_since_open(delivery)
      return nil unless delivery.opened_at

      (workout_started_at - delivery.opened_at).to_i
    end

    def attribution_props(delivery, seconds: nil)
      props = {
        notification_type: delivery.notification_type,
        delivery_id: delivery.id,
        workout_id: @session.workout_day_id,
        variant: @user.notification_preferences&.activation_push_variant
      }
      props[:seconds_to_workout_start] = seconds if seconds
      props.compact
    end

    def track_relationship_event(event_name, delivery, seconds_key: nil)
      metadata = {
        notification_type: delivery.notification_type,
        delivery_id: delivery.id,
        workout_id: @session.workout_day_id,
        platform: "android"
      }
      if seconds_key && delivery.opened_at
        metadata[seconds_key] = seconds_since_open(delivery)
      end

      UserEventService.track(
        user: @user,
        event_name: event_name,
        source: "activation_push",
        suppress_make_delivery: true,
        metadata: metadata
      )
    end
  end
end
