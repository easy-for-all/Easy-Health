require "yaml"

# Single interface over config/communication_events.yml — the canonical source
# of truth for which channels each business event routes to and the technical
# descriptors Make needs (push notification_type/route, email template_key,
# communication_type, engagement cap). Copy lives in Make, never here.
class CommunicationEvents
  ALLOWED_CHANNELS = %w[email push].freeze
  COMMUNICATION_TYPES = %w[lifecycle activation progress retention].freeze

  # Why an event deliberately never reaches Make. See
  # config/non_communication_events.yml for what each one means.
  NON_COMMUNICATION_REASONS = %w[
    push_telemetry
    product_analytics
    internal_audit
    legacy_inactive
    covered_by_other_event
  ].freeze

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

    # THE source of truth for "this fact must reach Make".
    #
    # An orchestration event is one with a YAML entry that is enabled and
    # declares at least one channel. There is deliberately NO separate
    # `orchestration:` key: it would be a fourth place to drift from (an event
    # with channels but `orchestration: false` means nothing coherent), and the
    # whole point of this layer is to have one catalog, not two.
    #
    # `enabled?` already requires a non-empty channel list; the second check is
    # kept explicit so the implementation cannot silently diverge from the
    # sentence above.
    def orchestration_event_names
      config.keys.select { |name| enabled?(name) && channels_for(name).any? }
    end

    def orchestration?(event_name)
      orchestration_event_names.include?(normalize_event_name(event_name))
    end

    # Event names that have a YAML entry (in file order), for audit/reporting.
    def configured_event_names
      config.keys
    end

    # --- The other half of the catalog --------------------------------------
    #
    # An event is either orchestration (entry in communication_events.yml) or
    # deliberately not communication (entry in non_communication_events.yml).
    # Anything in neither is `uncatalogued`: a fact nobody decided about. That
    # is not a harmless gap — it is how activation_workout_created spent months
    # being born `disabled` with nobody noticing, because the admin panel only
    # ever looked at events that were already in the catalog.

    def analytics_only_event_names
      non_communication_config.keys
    end

    def analytics_only?(event_name)
      non_communication_config.key?(normalize_event_name(event_name))
    end

    def analytics_only_reason_for(event_name)
      non_communication_config.dig(normalize_event_name(event_name), "reason")
    end

    # Registry events with no decision recorded in either file. Derived from
    # RelationshipEventTracker::EVENTS on purpose: the question is "which facts
    # this product emits have no orchestration decision", not "which strings
    # ever appeared in the user_events table". Names produced by other
    # subsystems are none of this catalog's business.
    def uncatalogued_event_names
      known_events - orchestration_event_names - analytics_only_event_names
    end

    def uncatalogued?(event_name)
      uncatalogued_event_names.include?(normalize_event_name(event_name))
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
    #
    # `uncatalogued` is deliberately NOT raised here. It is a real problem, but
    # it is a problem of a missing decision, not of a broken file — failing boot
    # in production because someone added an event name would be worse than the
    # gap it reports. It surfaces as a critical warning in the admin panel and
    # as a failing registry spec in CI, which is where a decision can be made.
    def validate!
      unknown = config.keys - known_events
      raise ConfigError, "unknown communication event(s): #{unknown.join(', ')}" if unknown.any?

      unknown_non_communication = non_communication_config.keys - known_events
      if unknown_non_communication.any?
        raise ConfigError, "unknown non-communication event(s): #{unknown_non_communication.join(', ')}"
      end

      both = config.keys & non_communication_config.keys
      if both.any?
        raise ConfigError,
              "event(s) declared as BOTH communication and non-communication: #{both.join(', ')}"
      end

      config.each { |name, cfg| validate_entry!(name, cfg) }
      non_communication_config.each { |name, cfg| validate_non_communication_entry!(name, cfg) }
      true
    end

    def reload!
      @config = nil
      @non_communication_config = nil
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

    def non_communication_config
      @non_communication_config ||= begin
        raw = YAML.safe_load_file(non_communication_config_path, aliases: false) || {}
        raw.each_with_object({}) do |(event_name, attrs), result|
          attrs = {} unless attrs.is_a?(Hash)
          result[normalize_event_name(event_name)] = { "reason" => attrs["reason"] }
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

    def validate_non_communication_entry!(name, cfg)
      return if NON_COMMUNICATION_REASONS.include?(cfg["reason"])

      raise ConfigError,
            "#{name}: reason must be one of #{NON_COMMUNICATION_REASONS.join(', ')}"
    end

    def config_path
      Rails.root.join("config/communication_events.yml")
    end

    def non_communication_config_path
      Rails.root.join("config/non_communication_events.yml")
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
