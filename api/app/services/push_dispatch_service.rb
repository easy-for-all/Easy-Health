require "digest"

# Sends a single scheduled NotificationDelivery via FCM. Revalidates eligibility
# immediately before sending (state may have changed since scheduling), claims
# the row atomically to avoid double-send across concurrent cron sweeps, updates
# status, invalidates dead tokens and controls retries.
class PushDispatchService
  MAX_RETRIES = 3
  RETRY_BACKOFF = ->(count) { (count**2 + 1).minutes }

  # Sweep entry point (called from the rake task). Synchronous by design.
  def self.dispatch_due(limit: 500, now: Time.current)
    stats = Hash.new(0)
    NotificationDelivery.due(now).order(:scheduled_for).limit(limit).find_each do |delivery|
      outcome = new(delivery).call
      stats[outcome] += 1
    end
    stats
  end

  def initialize(delivery)
    @delivery = delivery
    @user = delivery.user
  end

  def call
    return :skipped unless claim!

    reason = PushActivationEligibility.reason_ineligible(@user, notification_type: @delivery.notification_type)
    return skip(reason) if reason
    return skip("experiment_control") if ExperimentAssignment.variant_for(@user) == "control"

    send_to_devices
  end

  private

  attr_reader :delivery, :user

  # Atomic scheduled -> sending transition. Only the winner proceeds.
  def claim!
    NotificationDelivery
      .where(id: delivery.id, status: "scheduled")
      .update_all(status: "sending", updated_at: Time.current) == 1
  end

  def send_to_devices
    devices = user.device_tokens.active.to_a
    return skip("no_active_device") if devices.empty?

    message = ActivationPushMessages.build(notification_type: delivery.notification_type, user: user, delivery: delivery)
    service = FirebasePushService.new
    result = nil
    sent_device = nil

    devices.each do |device|
      result = service.deliver(token: device.token, title: message[:title], body: message[:body], data: message[:data])
      track_provider(result, device)
      device.invalidate!(result.error_code) if result.invalid_token
      if result.sent?
        sent_device = device
        break
      end
    end

    result&.sent? ? finalize_sent(result, sent_device) : finalize_failed(result)
  end

  def finalize_sent(result, device)
    delivery.update!(
      status: "sent",
      sent_at: Time.current,
      provider_message_id: result.message_id,
      push_device_id: device&.id,
      error_code: nil
    )
    stamp_preferences!
    track("push_sent")
    :sent
  end

  def finalize_failed(result)
    retry_count = delivery.retry_count + 1
    if retry_count >= MAX_RETRIES
      delivery.update!(status: "failed", retry_count: retry_count, error_code: result&.error_code)
      track("push_failed", error_code: result&.error_code)
      :failed
    else
      # Back to scheduled for a later sweep.
      delivery.update!(
        status: "scheduled",
        retry_count: retry_count,
        error_code: result&.error_code,
        scheduled_for: Time.current + RETRY_BACKOFF.call(retry_count)
      )
      :retried
    end
  end

  def stamp_preferences!
    prefs = user.notification_preferences!
    if delivery.notification_type == "first_workout_reminder"
      prefs.update!(activation_reminder_sent_at: Time.current)
    else
      # Recovery is the last activation push — end the flow.
      prefs.update!(
        activation_recovery_sent_at: Time.current,
        activation_notifications_completed_at: Time.current
      )
    end
  end

  def skip(reason)
    delivery.skip!(reason)
    track("notification_skipped", reason: reason)
    :skipped
  end

  # Records whether FCM ACCEPTED vs REJECTED the message for a device. This is
  # explicitly NOT "delivered to the phone" — that is proven only by an app-side
  # push_received/push_opened event. Token is never logged, only a SHA digest.
  def track_provider(result, device)
    track(
      result.sent? ? "push_provider_accepted" : "push_provider_rejected",
      provider_message_id: result.message_id,
      error_code: result.error_code,
      device_digest: device_digest(device.token)
    )
  end

  def device_digest(token)
    return nil if token.blank?

    Digest::SHA256.hexdigest(token)[0, 12]
  end

  def track(event_name, extra = {})
    UserEventService.track(
      user: user,
      event_name: event_name,
      metadata: base_metadata.merge(extra),
      source: "activation_push",
      suppress_make_delivery: true
    )
  end

  def base_metadata
    {
      notification_type: delivery.notification_type,
      delivery_id: delivery.id,
      correlation_id: "delivery-#{delivery.id}",
      platform: "android",
      variant: user.notification_preferences&.activation_push_variant
    }
  end
end
