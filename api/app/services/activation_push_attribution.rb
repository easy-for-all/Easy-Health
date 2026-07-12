# Attributes first-workout activation to a push ONLY when the user actually
# opened the push and then started/completed the workout within a window.
# Never attributes on send alone.
module ActivationPushAttribution
  START_WINDOW = 2.hours
  COMPLETE_WINDOW = 24.hours

  module_function

  # Called when a workout session starts. Cancels any pending activation push
  # (the user engaged) and, if a push was opened recently, records the conversion.
  def on_workout_started(user, session)
    NotificationDelivery.cancel_pending_for(user, reason: "workout_started")

    delivery = recently_opened(user, within: START_WINDOW)
    return if delivery.nil?

    delivery.update!(status: "converted", converted_at: Time.current) unless delivery.status == "converted"
    track(user, "workout_started_from_push", delivery, session, seconds_key: :seconds_to_workout_start)
  end

  # Called when a workout session completes. Attributes completion when the start
  # was already attributed to a push (converted delivery in the window).
  def on_workout_completed(user, session)
    delivery = attributed_delivery(user, within: COMPLETE_WINDOW)
    return if delivery.nil?

    track(user, "workout_completed_from_push", delivery, session)
  end

  def recently_opened(user, within:)
    user.notification_deliveries
        .where.not(opened_at: nil)
        .where(opened_at: within.ago..)
        .order(opened_at: :desc)
        .first
  end

  def attributed_delivery(user, within:)
    user.notification_deliveries
        .where(status: "converted")
        .where(converted_at: within.ago..)
        .order(converted_at: :desc)
        .first
  end

  def track(user, event_name, delivery, session, seconds_key: nil)
    metadata = {
      notification_type: delivery.notification_type,
      delivery_id: delivery.id,
      workout_id: session.workout_day_id,
      platform: "android"
    }
    if seconds_key && delivery.opened_at
      metadata[seconds_key] = (Time.current - delivery.opened_at).to_i
    end

    UserEventService.track(
      user: user,
      event_name: event_name,
      source: "activation_push",
      suppress_make_delivery: true,
      metadata: metadata
    )
  end
end
