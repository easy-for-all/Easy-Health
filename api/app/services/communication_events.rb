require "yaml"

# Single interface over config/communication_events.yml — the canonical source
# of truth for which channels each business event routes to and the technical
# descriptors Make needs (push notification_type/route, email template_key,
# communication_type, engagement cap). Copy lives in Make, never here.
class CommunicationEvents
  ALLOWED_CHANNELS = %w[email push].freeze
  COMMUNICATION_TYPES = %w[lifecycle activation progress retention].freeze

  class ConfigError < StandardError; end
  class UnknownEventError < ConfigError; end

  class << self
    # Full technical config for an event (channels/notification_type/route/
    # communication_type/engagement/enabled). Empty-ish hash for a known event
    # without a YAML entry.
    def config_for(event_name)
      name = normalize_event_name(event_name)
      validate_event_name!(name)

      config.fetch(name, default_config)
    end

    # A configured event may be turned off without deleting its entry. Known
    # events without a YAML entry are treated as disabled (no communication).
    def enabled?(event_name)
      cfg = config_for(event_name)
      cfg["enabled"] != false && Array(cfg["channels"]).any?
    end

    def channels_for(event_name)
      cfg = config_for(event_name)
      return [] if cfg["enabled"] == false

      Array(cfg["channels"])
    end

    def communication_type_for(event_name)
      config_for(event_name)["communication_type"]
    end

    def notification_type_for(event_name)
      config_for(event_name)["notification_type"]
    end

    def route_for(event_name)
      config_for(event_name)["route"]
    end

    def engagement?(event_name)
      config_for(event_name)["engagement"] == true
    end

    # Technical push descriptor (no copy). nil for events that do not push.
    def push_config_for(event_name)
      return nil unless channels_for(event_name).include?("push")

      {
        "notification_type" => notification_type_for(event_name),
        "route" => route_for(event_name),
        "campaign_key" => normalize_event_name(event_name)
      }
    end

    # Technical email descriptor. template_key defaults to the event_name; the
    # YAML may override it when the Make template key differs. nil for events
    # that do not email.
    def email_config_for(event_name)
      name = normalize_event_name(event_name)
      return nil unless channels_for(name).include?("email")

      { "template_key" => config_for(name)["template_key"].presence || name }
    end

    def known?(event_name)
      known_events.include?(normalize_event_name(event_name))
    end

    # Event names that have a YAML entry (in file order), for audit/reporting.
    def configured_event_names
      config.keys
    end

    # Validate a single configured entry. Raises ConfigError if invalid.
    def assert_entry!(event_name)
      name = normalize_event_name(event_name)
      validate_entry!(name, config.fetch(name, default_config))
      true
    end

    # Derived allowlist — events that route to push. Use this instead of a
    # parallel constant so the YAML stays the single source of truth.
    def push_events
      config.select { |name, _cfg| channels_for(name).include?("push") }.keys
    end

    def supports_channel?(event_name, channel)
      channels_for(event_name).include?(normalize_channel(channel))
    end

    def validate_channels!(channels)
      normalized = normalize_channels(channels)
      invalid = normalized - ALLOWED_CHANNELS
      raise ConfigError, "invalid communication channel(s): #{invalid.join(', ')}" if invalid.any?
      raise ConfigError, "duplicated communication channel(s): #{duplicates(normalized).join(', ')}" if duplicates(normalized).any?

      normalized
    end

    def validate_event_name!(event_name)
      name = normalize_event_name(event_name)
      return name if known_events.include?(name)

      raise UnknownEventError, "unknown communication event: #{name}"
    end

    # Boot/CI guard: every configured event must be structurally valid.
    def validate!
      unknown = config.keys - known_events
      raise ConfigError, "unknown communication event(s): #{unknown.join(', ')}" if unknown.any?

      config.each { |name, cfg| validate_entry!(name, cfg) }
      true
    end

    def reload!
      @config = nil
      @known_events = nil
      validate!
    end

    private

    def config
      @config ||= begin
        raw = YAML.safe_load_file(config_path, aliases: false) || {}
        raw.each_with_object({}) do |(event_name, attrs), result|
          attrs = {} unless attrs.is_a?(Hash)
          result[normalize_event_name(event_name)] = {
            "enabled" => attrs.fetch("enabled", true),
            "channels" => validate_channels!(attrs.fetch("channels", [])),
            "communication_type" => attrs["communication_type"],
            "notification_type" => attrs["notification_type"],
            "route" => attrs["route"],
            "template_key" => attrs["template_key"],
            "engagement" => attrs.fetch("engagement", false) == true
          }
        end
      end
    end

    def default_config
      { "enabled" => false, "channels" => [] }
    end

    def validate_entry!(name, cfg)
      unless [ true, false ].include?(cfg["enabled"])
        raise ConfigError, "#{name}: enabled must be a boolean"
      end
      return if cfg["enabled"] == false

      channels = validate_channels!(cfg["channels"])
      raise ConfigError, "#{name}: enabled event must declare at least one channel" if channels.empty?

      unless COMMUNICATION_TYPES.include?(cfg["communication_type"])
        raise ConfigError, "#{name}: communication_type must be one of #{COMMUNICATION_TYPES.join(', ')}"
      end

      if channels.include?("push")
        raise ConfigError, "#{name}: push events require notification_type" if cfg["notification_type"].blank?
        raise ConfigError, "#{name}: push events require route" if cfg["route"].blank?
      end
    end

    def config_path
      Rails.root.join("config/communication_events.yml")
    end

    def known_events
      @known_events ||= RelationshipEventTracker::EVENTS.map(&:to_s)
    end

    def normalize_event_name(event_name)
      event_name.to_s.strip
    end

    def normalize_channels(channels)
      Array(channels).map { |channel| normalize_channel(channel) }.reject(&:blank?)
    end

    def normalize_channel(channel)
      channel.to_s.strip
    end

    def duplicates(values)
      values.tally.select { |_value, count| count > 1 }.keys
    end
  end
end
