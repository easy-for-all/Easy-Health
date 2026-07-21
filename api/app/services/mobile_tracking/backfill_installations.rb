module MobileTracking
  # Backfills app_installations (and users.activation_platform) from the only
  # RELIABLE historical source: device_tokens. An Android device_token is proof
  # of a real native install — this is never behavioural inference.
  #
  # Idempotent (safe to re-run): each backfilled installation gets a deterministic
  # installation_id "dt-<device_token_id>", and activation_platform is only set
  # when blank (never reclassifies a user).
  #
  # Provenance is explicit: source = "backfill_device_token", so the panel can
  # tell an inferred historical install from one registered by the live tracker.
  # installed_at is left NULL (the real install date is unknown — never faked);
  # first_seen_at / tracking_started_at use the device_token's created_at.
  class BackfillInstallations
    SOURCE = "backfill_device_token".freeze

    Report = Struct.new(
      :dry_run, :device_tokens_scanned, :installations_created,
      :installations_existing, :activation_platform_backfilled,
      keyword_init: true
    ) do
      def to_h
        super.transform_values { |v| v }
      end
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
      @report = Report.new(
        dry_run: dry_run, device_tokens_scanned: 0, installations_created: 0,
        installations_existing: 0, activation_platform_backfilled: 0
      )
    end

    def call
      backfill_installations!
      backfill_activation_platform!
      @report
    end

    private

    def backfill_installations!
      DeviceToken.where(platform: "android").find_each(batch_size: 200) do |token|
        @report.device_tokens_scanned += 1
        installation_id = "dt-#{token.id}"

        if AppInstallation.exists?(installation_id: installation_id)
          @report.installations_existing += 1
          next
        end

        @report.installations_created += 1
        next if @dry_run

        AppInstallation.create!(
          installation_id: installation_id,
          user_id: token.user_id,
          device_token_id: token.id,
          platform: "android",
          native: true,
          app_version: token.app_version,
          notification_permission: token.permission_status,
          push_enabled: token.enabled,
          source: SOURCE,
          first_seen_at: token.created_at,
          tracking_started_at: token.created_at,
          last_seen_at: token.last_seen_at || token.created_at,
          last_authenticated_at: token.user_id ? token.created_at : nil
        )
      end
    end

    # Make the EXISTING platform-comparison cohort show real Android immediately:
    # stamp activation_platform="android" for users who own an Android device_token
    # and have never been classified. Never overwrites an existing value.
    def backfill_activation_platform!
      user_ids = DeviceToken.where(platform: "android")
                            .where.not(user_id: nil)
                            .distinct.pluck(:user_id)
      scope = User.where(id: user_ids, activation_platform: nil)

      @report.activation_platform_backfilled = scope.count
      return if @dry_run

      scope.update_all(activation_platform: "android")
    end
  end
end
