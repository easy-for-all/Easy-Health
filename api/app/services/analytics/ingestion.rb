module Analytics
  # Ingests a batch of product analytics events from the frontend.
  #
  # Responsibilities:
  #   - validate names/versions against the canonical taxonomy
  #   - only persist events whose sink includes "server"
  #   - sanitize properties (strip known sensitive keys)
  #   - idempotency via idempotency_key (duplicates are no-ops)
  #   - stamp received_at server-side
  #   - set users.activation_platform on the first event of a known user
  #   - record analytics_event_rejected for unknown events (no sensitive payload)
  #
  # Never raises to the caller for a single bad event — a failing event must not
  # drop the rest of the batch nor break the client.
  class Ingestion
    MAX_BATCH_SIZE = 50
    MAX_PROPERTIES_BYTES = 8_192

    Result = Struct.new(:accepted, :persisted, :skipped, :rejected, :rejections, keyword_init: true)

    def self.enabled?
      ENV.fetch("ANALYTICS_INGESTION_ENABLED", "true") != "false"
    end

    def initialize(user:, events:)
      @user = user
      @events = Array(events).first(MAX_BATCH_SIZE)
      @result = Result.new(accepted: 0, persisted: 0, skipped: 0, rejected: 0, rejections: [])
    end

    def call
      return @result unless self.class.enabled?

      @events.each { |raw| process(raw) }
      set_activation_platform!
      @result
    end

    private

    def process(raw)
      attrs = normalize(raw)
      name = attrs[:event_name]

      unless EventCatalog.known?(name)
        reject!(name, "unknown_event")
        return
      end

      @result.accepted += 1

      # Only server-sink events are persisted; ga4/clarity-only events reaching
      # this endpoint are accepted and ignored (the frontend should not send them).
      unless EventCatalog.server_tracked.include?(name)
        @result.skipped += 1
        return
      end

      persist(attrs)
    end

    def persist(attrs)
      ProductAnalyticsEvent.create!(attrs.merge(received_at: Time.current))
      @result.persisted += 1
    rescue ActiveRecord::RecordNotUnique
      # Duplicate idempotency_key — no-op, exactly-once semantics.
      @result.skipped += 1
    rescue ActiveRecord::RecordInvalid => e
      reject!(attrs[:event_name], "invalid: #{e.record.errors.full_messages.first}")
    end

    def normalize(raw)
      h = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
      h = h.symbolize_keys
      name = h[:event_name].to_s

      {
        event_name: name,
        event_version: coerce_version(h[:event_version], name),
        occurred_at: parse_time(h[:occurred_at]) || Time.current,
        user_id: @user&.id,
        anonymous_id: presence(h[:anonymous_id]),
        session_id: presence(h[:session_id]),
        platform: enum(h[:platform], EventCatalog::PLATFORMS),
        app_surface: enum(h[:app_surface], EventCatalog::APP_SURFACES),
        app_version: presence(h[:app_version]),
        build_number: presence(h[:build_number]),
        environment: enum(h[:environment], EventCatalog::ENVIRONMENTS, default: "production"),
        locale: presence(h[:locale]),
        timezone: presence(h[:timezone]),
        source: presence(h[:source]),
        properties: sanitized_properties(h[:properties]),
        idempotency_key: presence(h[:idempotency_key])
      }
    end

    def sanitized_properties(value)
      hash = value.is_a?(Hash) ? value : {}
      clean = RelationshipEventTracker.sanitize_metadata(hash)
      # Guard against oversized payloads.
      return {} if clean.to_json.bytesize > MAX_PROPERTIES_BYTES

      clean
    rescue StandardError
      {}
    end

    def set_activation_platform!
      return unless @user && @user.activation_platform.blank?

      platform = @events.map { |e| e.is_a?(Hash) || e.respond_to?(:to_unsafe_h) ? normalize(e)[:platform] : nil }
                        .compact.reject { |p| p == "unknown" }.first
      return if platform.blank?

      @user.update_column(:activation_platform, platform)
    rescue StandardError => e
      Rails.logger.warn("[analytics] activation_platform update failed: #{e.class}")
    end

    def reject!(name, reason)
      @result.rejected += 1
      @result.rejections << { event_name: name.to_s[0, 64], reason: reason }
      # Record for the Data Quality dashboard — never carries the original payload.
      ProductAnalyticsEvent.create!(
        event_name: "analytics_event_rejected",
        event_version: 1,
        occurred_at: Time.current,
        received_at: Time.current,
        user_id: @user&.id,
        platform: "unknown",
        app_surface: "unknown",
        environment: Rails.env.to_s,
        properties: { rejected_event_name: name.to_s[0, 64], reason: reason }
      )
    rescue StandardError => e
      Rails.logger.warn("[analytics] reject logging failed: #{e.class}")
    end

    def coerce_version(value, name)
      value.presence&.to_i || EventCatalog.current_version(name) || 1
    end

    def enum(value, allowed, default: "unknown")
      allowed.include?(value.to_s) ? value.to_s : default
    end

    def parse_time(value)
      return value if value.is_a?(Time) || value.is_a?(ActiveSupport::TimeWithZone)
      Time.zone.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def presence(value)
      value.to_s.presence
    end
  end
end
