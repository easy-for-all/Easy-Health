# Funnel analytics for the push journey V1. Emits safe funnel events into
# user_events (never a token; always suppressed from Make delivery so they don't
# loop back through the webhook). Dimensions are kept minimal and consistent.
module PushJourney
  ENGAGEMENT_CATEGORIES = %w[activation_reminder workout_reminder].freeze

  module_function

  def track_eligible(user:, event_name:, metadata: {})
    emit("push_event_eligible", user: user, event_name: event_name, metadata: metadata)
  end

  def track_requested_to_make(user:, event_name:, metadata: {})
    emit("push_requested_to_make", user: user, event_name: event_name, metadata: metadata)
  end

  def track_dispatch_skipped(user:, event_name:, metadata: {})
    emit("push_dispatch_skipped", user: user, event_name: event_name, metadata: metadata)
  end

  def emit(analytics_event, user:, event_name:, metadata:)
    UserEventService.track(
      user: user,
      event_name: analytics_event,
      source: "push_journey",
      suppress_make_delivery: true,
      metadata: { event_name: event_name.to_s }.merge(metadata)
    )
  end
end
