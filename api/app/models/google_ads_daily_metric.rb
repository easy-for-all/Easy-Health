# One row per (reporting date, campaign) of the Google Ads Android campaign.
#
# This table is a CACHE of what Google attributed, never a source of product
# truth. The Admin endpoint reads only from here — it must never call the Google
# Ads API on a page load. Writes happen exclusively in
# GoogleAds::AndroidAcquisitionSync, driven by cron.
#
# No credential, token or OAuth material is ever stored here.
class GoogleAdsDailyMetric < ApplicationRecord
  UNIQUE_INDEX = :idx_google_ads_daily_metrics_date_campaign

  validates :date, presence: true
  validates :campaign_id, presence: true

  scope :for_campaign, ->(campaign_id) { where(campaign_id: campaign_id.to_s) }
  scope :between, ->(start_date, end_date) { where(date: start_date..end_date) }

  def cost_brl
    cost_micros.to_i / 1_000_000.0
  end
end
