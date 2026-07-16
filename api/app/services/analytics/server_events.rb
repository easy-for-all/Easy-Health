module Analytics
  # Records a server-originated auditable event directly into
  # product_analytics_events (bypassing the HTTP ingestion endpoint), for events
  # that are computed on the backend — e.g. push attribution — rather than
  # emitted by the client. Only server-sink taxonomy events are accepted.
  #
  # Non-raising: analytics must never break a business flow.
  module ServerEvents
    module_function

    def record(event_name:, user: nil, platform: "unknown", properties: {}, occurred_at: Time.current, idempotency_key: nil, source: "easyhealth_backend")
      name = event_name.to_s
      return unless EventCatalog.server_tracked.include?(name)

      ProductAnalyticsEvent.create!(
        event_name: name,
        event_version: EventCatalog.current_version(name) || 1,
        occurred_at: occurred_at,
        received_at: Time.current,
        user_id: user&.id,
        platform: EventCatalog::PLATFORMS.include?(platform.to_s) ? platform.to_s : "unknown",
        app_surface: "unknown",
        environment: Rails.env.to_s,
        source: source,
        properties: RelationshipEventTracker.sanitize_metadata(properties || {}),
        idempotency_key: idempotency_key
      )
    rescue ActiveRecord::RecordNotUnique
      # Idempotent no-op — the event was already recorded.
      nil
    rescue StandardError => e
      Rails.logger.warn("[analytics] server event #{event_name} failed: #{e.class}")
      nil
    end
  end
end
