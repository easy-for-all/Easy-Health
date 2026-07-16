module Analytics
  # Loads and exposes the canonical event taxonomy (config/analytics/events.yml).
  # Single source of truth shared with the frontend (parity enforced by a spec).
  module EventCatalog
    CONFIG_PATH = Rails.root.join("config", "analytics", "events.yml")

    # Allowed dimension enums (mirrors docs/analytics/EVENT_TAXONOMY.md).
    PLATFORMS     = %w[android web pwa unknown].freeze
    APP_SURFACES  = %w[native_shell mobile_web desktop_web installed_pwa browser_pwa unknown].freeze
    ENVIRONMENTS  = %w[production staging development test].freeze
    SINKS         = %w[server ga4 clarity].freeze

    class << self
      def data
        @data ||= load!
      end

      def reload!
        @data = load!
      end

      def taxonomy_version
        data.fetch("taxonomy_version", 1)
      end

      def events
        data.fetch("events", {})
      end

      def names
        events.keys
      end

      def known?(event_name)
        events.key?(event_name.to_s)
      end

      def definition(event_name)
        events[event_name.to_s]
      end

      def current_version(event_name)
        definition(event_name)&.fetch("version", 1)
      end

      # Events routed to a given sink ("server" | "ga4" | "clarity").
      def names_for_sink(sink)
        events.select { |_name, meta| Array(meta["sinks"]).include?(sink.to_s) }.keys
      end

      def server_tracked
        names_for_sink("server")
      end

      def valid_platform?(value)
        PLATFORMS.include?(value.to_s)
      end

      def valid_app_surface?(value)
        APP_SURFACES.include?(value.to_s)
      end

      def valid_environment?(value)
        ENVIRONMENTS.include?(value.to_s)
      end

      private

      def load!
        raw = YAML.safe_load_file(CONFIG_PATH)
        raw.freeze
        raw
      end
    end
  end
end
