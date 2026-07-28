module AppInstallations
  # Idempotent upsert of an app installation, keyed by installation_id.
  #
  # - Accepts anonymous installs (user may be nil pre-login).
  # - user comes ONLY from the authenticated session — never from the payload.
  # - On first sight, stamps first_seen_at + tracking_started_at.
  # - Always refreshes last_seen_at; delegates any user link to LinkToUser.
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

    # Explicit outcome vocabulary so the controller can answer with a truthful
    # contract instead of collapsing "disabled", "invalid payload" and "we broke"
    # into one opaque acceptance.
    #
    #   :registered        — the row exists and was persisted
    #   :disabled          — kill-switch off; nothing was written, never retry
    #   :invalid_input     — the request itself is unusable (blank installation_id)
    #   :validation_failed — the payload reached the DB and was rejected
    #   :unexpected_error  — transient/internal; a later retry may succeed
    STATUSES = %i[registered disabled invalid_input validation_failed unexpected_error].freeze

    Result = Struct.new(:installation, :created, :ok, :link_result, :status, keyword_init: true)

    # Default-ON kill-switch: tracking runs unless MOBILE_ANALYTICS_ENABLED is
    # explicitly set to a falsey value. An unset env keeps it enabled.
    def self.enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("MOBILE_ANALYTICS_ENABLED", "true"))
    end

    def self.install_referrer_enabled?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch("INSTALL_REFERRER_ENABLED", "false"))
    end

    def initialize(user:, installation_id:, attributes: {}, session_started: false)
      @user = user
      @installation_id = installation_id.to_s.strip
      @attributes = attributes || {}
      @session_started = ActiveModel::Type::Boolean.new.cast(session_started)
    end

    def call
      return failed(:disabled) unless self.class.enabled?
      return failed(:invalid_input) if @installation_id.blank?

      install, created = upsert!
      record_authenticated_request!(install)
      link_result = link_user!(install)
      Rails.logger.info(structured_log(install, created))
      Result.new(installation: install, created: created, ok: true, status: :registered, link_result: link_result)
    rescue ActiveRecord::RecordInvalid => e
      # A real validation failure. Reported as such so the client learns its
      # payload is the problem instead of retrying it forever.
      Rails.logger.warn("[installations] register rejected: #{e.class}: #{e.message}")
      failed(:validation_failed)
    rescue StandardError => e
      # Never break the caller (tracking is best-effort), but keep the failure
      # observable — a swallowed DB/schema/programming error must reach Sentry.
      Rails.logger.warn("[installations] register failed: #{e.class}: #{e.message}")
      Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
      failed(:unexpected_error)
    end

    private

    def failed(status)
      Result.new(installation: nil, created: false, ok: false, status: status)
    end

    # find_or_initialize_by + save! is not atomic: two boots of the same fresh
    # install can both see "no row" and both INSERT. The unique index makes the
    # loser raise, and losing that request would leave the app with no row and
    # nothing to link to.
    #
    # Exactly ONE recovery: reload by installation_id and continue as an update.
    # If that fails too, the error propagates (no loop, no retry storm).
    def upsert!
      install = AppInstallation.find_or_initialize_by(installation_id: @installation_id)
      created = install.new_record?

      apply_attributes!(install, created)
      install.save!
      [ install, created ]
    rescue ActiveRecord::RecordNotUnique
      recover_from_create_race!
    rescue ActiveRecord::RecordInvalid => e
      # The same race, one step earlier: the uniqueness VALIDATOR saw the winner's
      # row, so save! raises RecordInvalid instead of RecordNotUnique. This is the
      # likelier shape (the validator SELECTs before inserting) and it must not be
      # reported as a rejected payload — the row exists, the client is not at fault.
      raise unless taken_installation_id?(e.record)

      recover_from_create_race!
    end

    # Only the id-collision race recovers. Any other validation error is the
    # payload's own problem and must keep reporting validation_failed.
    def taken_installation_id?(record)
      return false if record.nil?

      record.errors.of_kind?(:installation_id, :taken)
    end

    def recover_from_create_race!
      install = AppInstallation.find_by(installation_id: @installation_id)
      # Not a race after all (some other unique constraint): let the caller
      # classify it, rather than reporting a registration that never happened.
      raise if install.nil?

      Rails.logger.info("[installations] register race recovered by reload")
      # The winner already created the row; this request is now an update. It
      # brings only its own metadata — user_id belongs to LinkToUser alone.
      apply_attributes!(install, false)
      install.save! if install.changed?
      [ install, false ]
    end

    def apply_attributes!(install, created)
      apply_context!(install)
      apply_referrer!(install)
      stamp_timeline!(install, created)
    end

    def apply_context!(install)
      allowed = @attributes.to_h.symbolize_keys.slice(*ALLOWED_ATTRS)
      allowed.each do |key, value|
        coerced = coerce(key, value)
        next if coerced.nil? && install.persisted?

        install.public_send("#{key}=", coerced)
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
      # last_seen_at: any valid contact with the backend.
      install.last_seen_at = now
      # last_session_at: ONLY a real native session start (app boot), signalled
      # explicitly by the caller — never inflated by a login re-register or a refresh.
      install.last_session_at = now if @session_started
      # installed_at is never invented here when unknown.
    end

    def record_authenticated_request!(install)
      return if @user.nil?
      return if install.first_authenticated_request_at.present?

      now = Time.current
      install.update_columns(first_authenticated_request_at: now, updated_at: now)
    rescue StandardError => e
      Rails.logger.warn("[installations] authenticated_request_signal failed: #{e.class}: #{e.message}")
    end

    def link_user!(install)
      return nil if @user.nil?

      result = AppInstallations::LinkToUser.call(
        installation: install,
        user: @user,
        source: "register",
        runtime_context: runtime_context_for(install),
        build_number: install.app_build
      )
      backfill_activation_platform!(install) if result.success
      result
    end

    # Fill User#activation_platform from a native Android install the first time it
    # is associated, but only when it is still blank — an existing valid origin is
    # never overwritten. Idempotent and non-blocking.
    def backfill_activation_platform!(install)
      return unless install.native && install.platform == "android"
      return if @user.activation_platform.present?

      @user.update_column(:activation_platform, "android")
    rescue StandardError => e
      Rails.logger.warn("[installations] activation_platform set failed: #{e.class}: #{e.message}")
    end

    def structured_log(install, created)
      {
        event: created ? "installation_registered" : "installation_refreshed",
        installation_id_hash: Digest::SHA256.hexdigest(install.installation_id.to_s)[0, 12],
        platform: install.platform,
        native: install.native,
        authenticated: install.user_id.present?
      }.to_json
    end

    def runtime_context_for(install)
      AppInstallations::RequestContext::RUNTIME_BY_PLATFORM.fetch(
        install.platform.to_s,
        AppInstallations::RequestContext::UNKNOWN_RUNTIME
      )
    end
  end
end
