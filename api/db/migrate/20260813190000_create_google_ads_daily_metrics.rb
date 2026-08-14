class CreateGoogleAdsDailyMetrics < ActiveRecord::Migration[8.1]
  def change
    create_table :google_ads_daily_metrics do |t|
      # segments.date as Google Ads reports it. NOT the same clock as
      # users.created_at, which is cut in America/Sao_Paulo — the two are shown
      # side by side and never divided by each other.
      t.date :date, null: false
      t.string :campaign_id, null: false
      t.string :campaign_name

      t.bigint :impressions, default: 0, null: false
      t.bigint :clicks, default: 0, null: false
      # Cost comes ONLY from the unsegmented performance query. Reading it from
      # the conversion-segmented query would multiply it by the number of
      # conversion actions of the day.
      t.bigint :cost_micros, default: 0, null: false

      # Decimal, never integer: Google's attribution model produces fractional
      # conversions (data-driven / cross-device), and .to_i would silently
      # truncate 0.83 installs to 0.
      t.decimal :installs, precision: 12, scale: 2, default: 0, null: false
      t.decimal :sign_ups, precision: 12, scale: 2, default: 0, null: false

      t.datetime :synced_at, null: false

      t.timestamps
    end

    # Named explicitly so upsert_all can reference the index by name instead of
    # by column list — there is then no ambiguity about which constraint the
    # conflict resolves against.
    add_index :google_ads_daily_metrics,
              [ :date, :campaign_id ],
              unique: true,
              name: "idx_google_ads_daily_metrics_date_campaign"
  end
end
