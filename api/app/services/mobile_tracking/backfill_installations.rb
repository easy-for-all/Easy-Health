module MobileTracking
  # Read-only diagnostic for the old device_token-based backfill idea.
  #
  # A device_token proves push/auth activity, but it does not deterministically
  # identify which AppInstallation row belongs to that user. The live repair now
  # relies on X-Installation-Id + authenticated requests, so this class must not
  # create app_installations or write app_installations.user_id.
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
      report_installation_candidates
      report_activation_platform_candidates
      @report
    end

    private

    def report_installation_candidates
      DeviceToken.where(platform: "android").find_each(batch_size: 200) do |token|
        @report.device_tokens_scanned += 1
        installation_id = "dt-#{token.id}"

        if AppInstallation.exists?(installation_id: installation_id)
          @report.installations_existing += 1
          next
        end

        @report.installations_created += 1
      end
    end

    def report_activation_platform_candidates
      user_ids = DeviceToken.where(platform: "android")
                            .where.not(user_id: nil)
                            .distinct.pluck(:user_id)
      scope = User.where(id: user_ids, activation_platform: nil)

      @report.activation_platform_backfilled = scope.count
    end
  end
end
