# Attributes first-workout activation to a push ONLY when the user actually
# opened the push and then started/completed the workout within a window.
# Never attributes on send alone.
#
# The attribution RULES live in Analytics::PushAttributionService (documented,
# testable, and mirrored into product_analytics_events). This module keeps the
# activation-specific side effect (cancelling pending pushes) and delegates.
module ActivationPushAttribution
  START_WINDOW = Analytics::PushAttributionService::START_WINDOW
  COMPLETE_WINDOW = Analytics::PushAttributionService::COMPLETE_WINDOW

  module_function

  # Called when a workout session starts. Cancels any pending activation push
  # (the user engaged) and, if a push was opened recently, records the conversion.
  def on_workout_started(user, session)
    NotificationDelivery.cancel_pending_for(user, reason: "workout_started")
    Analytics::PushAttributionService.attribute_start(user, session)
  end

  # Called when a workout session completes. Attributes completion when the start
  # was already attributed to a push (converted delivery in the window).
  def on_workout_completed(user, session)
    Analytics::PushAttributionService.attribute_completion(user, session)
  end
end
