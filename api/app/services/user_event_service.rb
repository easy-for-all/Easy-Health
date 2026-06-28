class UserEventService
  EVENTS = RelationshipEventTracker::EVENTS

  def self.track(user:, event: nil, event_name: nil, metadata: {}, source: "easyhealth_backend",
                 occurred_at: Time.current, idempotency_key: nil, suppress_make_delivery: false)
    name = (event_name || event).to_s
    return unless EVENTS.include?(name)

    RelationshipEventTracker.track(
      user: user,
      event_name: name,
      metadata: metadata,
      source: source,
      occurred_at: occurred_at,
      idempotency_key: idempotency_key,
      suppress_make_delivery: suppress_make_delivery
    )
  rescue => e
    Rails.logger.warn("[UserEvent] Failed to track #{event || event_name} for user #{user&.id}: #{e.message}")
  end
end
