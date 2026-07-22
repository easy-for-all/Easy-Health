module AppInstallations
  # Idempotent upsert of an app installation, keyed by installation_id.
  #
  # - Accepts anonymous installs (user may be nil pre-login).
  # - user comes ONLY from the authenticated session — never from the payload.
  # - On first sight, stamps first_seen_at + tracking_started_at.
  # - Always refreshes last_seen_at; associates the user when present.
  # - Never raises to the caller for a bad field — tracking must not break the app.
  #
  # Feature-flagged by MOBILE_ANALYTICS_ENABLED (default off): when disabled the
  # call is a no-op so the endpoint can ship dark.
  class Register
    # Client-supplied fields allowed onto the record (allowlist — no user_id, no
    # PII, no FCM token).
    ALLOWED_ATTRS = %i[
      platform native operating_system operating_system_version
      app_version app_build device_manufacturer device_model
      locale timezone notification_permission push_enabled
      analytics_consent tracking_version
    ].freeze

    # Install-referrer attributes, gated by INSTALL_REFERRER_ENABLED and written
    # ONCE (first valid attribution; never overwritten by a blank).
    REFERRER_ATTRS = %i[
      install_referrer utm_source utm_medium utm_campaign
      referrer_source referrer_click_at install_begin_at
    ].freeze

    MAX_STRING_BYTES = 256

    Result = Struct.new(:installation, :created, :ok, keyword_init: true)

    def self.enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("MOBILE_ANALYTICS_ENABLED", "false"))
    end

    def self.install_referrer_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("INSTALL_REFERRER_ENABLED", "false"))
    end

    def initialize(user:, installation_id:, attributes: {})
      @user = user
      @installation_id = installation_id.to_s.strip
      @attributes = attributes || {}
    end

    def call
      return Result.new(installation: nil, created: false, ok: false) unless self.class.enabled?
      return Result.new(installation: nil, created: false, ok: false) if @installation_id.blank?

      install = AppInstallation.find_or_initialize_by(installation_id: @installation_id)
      created = install.new_record?

      apply_context!(install)
      apply_referrer!(install)
      stamp_timeline!(install, created)
      associate_user!(install)

      install.save!
      Rails.logger.info(structured_log(install, created))
      Result.new(installation: install, created: created, ok: true)
    rescue StandardError => e
      Rails.logger.warn("[installations] register failed: #{e.class}: #{e.message}")
      Result.new(installation: nil, created: false, ok: false)
    end

    private

    def apply_context!(install)
      allowed = @attributes.to_h.symbolize_keys.slice(*ALLOWED_ATTRS)
      allowed.each do |key, value|
        install.public_send("#{key}=", coerce(key, value))
      end
      install.source ||= "register"
    end

    # First valid attribution wins: only set the referrer when the flag is on and
    # the install has none yet, and never overwrite it with a blank.
    def apply_referrer!(install)
      return unless self.class.install_referrer_enabled?
      return if install.install_referrer.present?

      referrer = @attributes.to_h.symbolize_keys.slice(*REFERRER_ATTRS)
      return if referrer.values.all?(&:blank?)

      referrer.each { |key, value| install.public_send("#{key}=", value.presence) }
    end

    def coerce(key, value)
      case key
      when :native, :push_enabled, :analytics_consent
        ActiveModel::Type::Boolean.new.cast(value)
      when :tracking_version
        value.to_s.presence&.to_i
      else
        truncate(value)
      end
    end

    def truncate(value)
      str = value.to_s
      return nil if str.blank?

      str.byteslice(0, MAX_STRING_BYTES)&.scrub || str[0, MAX_STRING_BYTES]
    end

    def stamp_timeline!(install, created)
      now = Time.current
      if created
        install.first_seen_at ||= now
        install.tracking_started_at ||= now
      end
      install.last_seen_at = now
    end

    def associate_user!(install)
      return if @user.nil?

      install.user = @user
      install.last_authenticated_at = Time.current
    end

    def structured_log(install, created)
      {
        event: created ? "installation_registered" : "installation_refreshed",
        installation_id: install.installation_id,
        platform: install.platform,
        native: install.native,
        authenticated: install.user_id.present?
      }.to_json
    end
  end
end
