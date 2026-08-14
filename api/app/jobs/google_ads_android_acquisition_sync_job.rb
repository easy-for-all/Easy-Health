# Refreshes the Google Ads cache for the Android campaign.
#
# Driven by external cron (see lib/tasks/google_ads.rake) — it does NOT
# reschedule itself, following the same discipline as
# ObservabilityHealthCheckJob. The heartbeat makes a cron that stopped running
# visible in the observability panel instead of silently freezing the numbers.
#
# Idempotent: it re-syncs a rolling window every run, and the upsert makes a
# repeated run a no-op in terms of rows.
class GoogleAdsAndroidAcquisitionSyncJob < ApplicationJob
  queue_as :default

  def self.observability_heartbeat_key
    Analytics::AndroidAcquisition::HEARTBEAT_KEY
  end

  def perform(days: GoogleAds::AndroidAcquisitionSync::DEFAULT_LOOKBACK_DAYS)
    result = GoogleAds::AndroidAcquisitionSync.new(days: days).call

    case result.status
    when "not_configured"
      # Not a failure: a server without credentials must not raise every hour.
      # The panel already reports this state to the admin.
      Rails.logger.info(
        "[GoogleAdsAndroidAcquisitionSyncJob] not configured (missing: #{result.missing.join(', ')})"
      )
    else
      Rails.logger.info(
        "[GoogleAdsAndroidAcquisitionSyncJob] synced #{result.rows_written} day(s) " \
        "#{result.start_date}..#{result.end_date} campaign=#{result.campaign_id}"
      )
    end

    result
  end
end
