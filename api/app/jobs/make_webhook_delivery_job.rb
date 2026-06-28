class MakeWebhookDeliveryJob < ApplicationJob
  queue_as :default

  MAX_ATTEMPTS = 5

  def perform(user_event_id)
    user_event = UserEvent.find_by(id: user_event_id)
    return unless user_event
    return if user_event.make_delivery_status == "delivered"

    if user_event.make_attempts_count.to_i >= MAX_ATTEMPTS
      user_event.update!(
        make_delivery_status: "failed",
        make_last_error: "max_attempts_reached"
      )
      return
    end

    result = MakeWebhookClient.new.deliver(user_event)
    user_event.reload

    return unless result.status == "failed"
    return if user_event.make_attempts_count.to_i >= MAX_ATTEMPTS

    self.class.set(wait: backoff_for(user_event.make_attempts_count)).perform_later(user_event.id)
  end

  private

  def backoff_for(attempts_count)
    attempts = [attempts_count.to_i, 1].max
    (attempts * attempts).minutes
  end
end
