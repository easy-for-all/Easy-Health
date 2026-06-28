class MakeWebhookEligibility
  def self.enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("MAKE_WEBHOOK_ENABLED", "false"))
  end

  def self.webhook_url
    ENV["MAKE_WEBHOOK_URL"].to_s
  end

  def self.webhook_secret
    ENV["MAKE_WEBHOOK_SECRET"].to_s
  end

  def self.timeout_seconds
    ENV.fetch("MAKE_WEBHOOK_TIMEOUT_SECONDS", "10").to_i.clamp(1, 30)
  end

  def self.payload_mode
    mode = ENV.fetch("MAKE_WEBHOOK_PAYLOAD_MODE", "minimal").to_s
    %w[full minimal].include?(mode) ? mode : "minimal"
  end

  def self.allowed_events
    ENV.fetch("MAKE_WEBHOOK_ALLOWED_EVENTS", "")
       .split(",")
       .map(&:strip)
       .reject(&:blank?)
  end

  def self.event_allowed?(event_name)
    allowed_events.include?(event_name.to_s)
  end

  def self.configured?
    enabled? && webhook_url.present? && webhook_secret.present?
  end

  def self.eligible_for_new_event?(user:, event_name:, suppress_make_delivery: false)
    return false if suppress_make_delivery
    return false unless configured?
    return false unless event_allowed?(event_name)

    user_eligible_for_relationship?(user)
  end

  def self.deliverable?(user_event)
    return false unless user_event
    return false if user_event.make_delivery_status == "delivered"

    eligible_for_new_event?(
      user: user_event.user,
      event_name: user_event.event_name,
      suppress_make_delivery: false
    )
  end

  def self.ineligibility_reason(user_event)
    return "make_webhook_disabled_or_unconfigured" unless configured?
    return "event_not_allowed_for_make" unless event_allowed?(user_event.event_name)
    return "user_not_eligible_for_relationship" unless user_eligible_for_relationship?(user_event.user)

    "not_deliverable"
  end

  def self.user_eligible_for_relationship?(user)
    return false unless user
    return false if user.respond_to?(:deletion_requested_at) && user.deletion_requested_at.present?
    return false if user.respond_to?(:anonymized_at) && user.anonymized_at.present?
    return false if user.respond_to?(:marketing_consent?) && !user.marketing_consent?
    return false if user.respond_to?(:unsubscribed_at) && user.unsubscribed_at.present?
    return false if user.respond_to?(:email_bounced_at) && user.email_bounced_at.present?
    return false if user.email.blank?
    return false if user.email.end_with?("@easyhealth.invalid")

    true
  end
end
