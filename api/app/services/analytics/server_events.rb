module Analytics
  # Records a server-originated auditable event directly into
  # product_analytics_events (bypassing the HTTP ingestion endpoint), for events
  # that are computed on the backend — e.g. push attribution — rather than
  # emitted by the client. Only server-sink taxonomy events are accepted.
  #
  # Non-raising: analytics must never break a business flow.
  module ServerEvents
    module_function

    # The dimension keyword arguments default to Observability::Context, so an
    # event recorded during a request automatically inherits the app version,
    # build and session that request carried — without every caller having to
    # thread them through. All are optional and nil-safe, so existing callers
    # keep working unchanged.
    def record(event_name:, user: nil, platform: nil, properties: {}, occurred_at: Time.current,
               idempotency_key: nil, source: "easyhealth_backend", app_surface: nil,
               app_version: nil, build_number: nil, session_id: nil, anonymous_id: nil)
      name = event_name.to_s
      return unless EventCatalog.server_tracked.include?(name)

      resolved_platform = platform.presence || context_value(:platform) || "unknown"

      ProductAnalyticsEvent.create!(
        event_name: name,
        event_version: EventCatalog.current_version(name) || 1,
        occurred_at: occurred_at,
        received_at: Time.current,
        user_id: user&.id || context_value(:user_id),
        platform: EventCatalog::PLATFORMS.include?(resolved_platform.to_s) ? resolved_platform.to_s : "unknown",
        app_surface: EventCatalog::APP_SURFACES.include?(app_surface.to_s) ? app_surface.to_s : "unknown",
        app_version: app_version.presence || context_value(:app_version),
        build_number: build_number.presence || context_value(:app_build),
        session_id: session_id.presence || context_value(:session_id),
        anonymous_id: anonymous_id.presence,
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

    # Reads the request/job context without hard-coupling this service to it:
    # ServerEvents predates Observability and must keep working if it is absent.
    def context_value(attribute)
      return nil unless defined?(Observability::Context)

      Observability::Context.public_send(attribute).presence
    rescue StandardError
      nil
    end
  end
end
