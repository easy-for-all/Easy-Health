class MakeWebhookDeliveryJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = MakeWebhookClient::MAX_ATTEMPTS

  def perform(user_event_id)
    user_event = UserEvent.find_by(id: user_event_id)
    return unless user_event
    return if user_event.make_delivery_status == "accepted_by_make"

    if user_event.make_attempts_count.to_i >= MAX_ATTEMPTS
      user_event.update!(
        make_delivery_status: "dead_letter",
        make_last_error: "max_attempts_reached",
        make_last_error_message: "max_attempts_reached",
        make_next_retry_at: nil
      )
      return
    end

    attempt = user_event.make_attempts_count.to_i + 1
    result = MakeWebhookClient.new.deliver(user_event)
    user_event.reload

    if user_event.make_delivery_status == "accepted_by_make"
      Observability::Heartbeat.succeeded!("make_webhook_delivery")
      Observability::Events.integration_delivery_succeeded(integration: "make", attempt: attempt)
    else
      Observability::Heartbeat.failed!("make_webhook_delivery", error_code: user_event.make_last_error)
      Observability::Events.integration_delivery_failed(
        integration: "make",
        error_code: user_event.make_last_error.presence || "delivery_failed",
        attempt: attempt
      )
    end

    return unless result.retryable?
    return if user_event.make_attempts_count.to_i >= MAX_ATTEMPTS

    if user_event.make_next_retry_at.present?
      self.class.set(wait_until: user_event.make_next_retry_at).perform_later(user_event.id)
    else
      self.class.set(wait: MakeWebhookClient.retry_backoff_for(user_event.make_attempts_count)).perform_later(user_event.id)
    end
  end
end
