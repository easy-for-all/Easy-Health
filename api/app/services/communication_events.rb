require "yaml"

class CommunicationEvents
  ALLOWED_CHANNELS = %w[email push].freeze

  class ConfigError < StandardError; end
  class UnknownEventError < ConfigError; end

  class << self
    def channels_for(event_name)
      name = normalize_event_name(event_name)
      validate_event_name!(name)

      config.fetch(name, [])
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

    def validate!
      unknown = config.keys - known_events
      raise ConfigError, "unknown communication event(s): #{unknown.join(', ')}" if unknown.any?

      config.each_value { |channels| validate_channels!(channels) }
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
          channels = attrs.is_a?(Hash) ? attrs.fetch("channels", []) : []
          result[normalize_event_name(event_name)] = validate_channels!(channels)
        end
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
