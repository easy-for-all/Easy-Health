class CommunicationTime
  DEFAULT_ZONE_NAME = "America/Sao_Paulo".freeze
  DEFAULT_DAILY_SCHEDULE = "daily 08:00 America/Sao_Paulo".freeze

  class << self
    def default_zone_name
      configured = ENV["COMMUNICATION_DEFAULT_TIMEZONE"].to_s.presence || DEFAULT_ZONE_NAME
      valid_zone_name(configured) || DEFAULT_ZONE_NAME
    end

    def default_zone
      zone_for_name(default_zone_name) || zone_for_name(DEFAULT_ZONE_NAME)
    end

    def zone_for(user)
      zone_from_sources(user) || default_zone
    end

    def zone_name_for(user)
      zone_for(user).tzinfo.name
    end

    def valid_zone_name(value)
      zone_for_name(value)&.tzinfo&.name
    end

    private

    def zone_from_sources(user)
      return nil unless user

      timezone_sources(user).each do |source, value|
        next if value.blank?

        zone = zone_for_name(value)
        return zone if zone

        warn_invalid_timezone(source)
      end

      nil
    end

    def timezone_sources(user)
      [
        [ "notification_preferences", user.notification_preferences&.timezone ],
        [ "user", user.time_zone ],
        [ "app_installation", latest_android_installation_timezone(user) ]
      ]
    end

    # AppInstallation is a fallback signal only: it never wins over an explicit
    # notification/user timezone, and it is scoped to a linked Android install.
    def latest_android_installation_timezone(user)
      return nil unless user&.id

      AppInstallation
        .for_platform("android")
        .where(user_id: user.id)
        .where.not(timezone: [ nil, "" ])
        .order(Arel.sql("COALESCE(last_authenticated_at, last_seen_at, updated_at, created_at) DESC"))
        .limit(1)
        .pick(:timezone)
    rescue StandardError => e
      Rails.logger.warn("[communication_time] app_installation_timezone_lookup_failed error=#{e.class}")
      nil
    end

    def zone_for_name(value)
      ActiveSupport::TimeZone[value.to_s]
    rescue TZInfo::InvalidTimezoneIdentifier, ArgumentError
      nil
    end

    def warn_invalid_timezone(source)
      Rails.logger.warn("[communication_time] invalid_timezone source=#{source}")
    end
  end
end
