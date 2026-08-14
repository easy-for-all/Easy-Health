module GoogleAds
  # Pulls what Google Ads attributed to the Android app campaign and caches it
  # in google_ads_daily_metrics.
  #
  # TWO INDEPENDENT QUERIES, ON PURPOSE. Segmenting by conversion_action
  # multiplies every row of the day by the number of conversion actions that
  # fired, so a campaign with three actions would report three times the spend.
  # Cost, impressions and clicks therefore come ONLY from the unsegmented
  # performance query; conversions come only from the segmented one.
  #
  # There is no "installs" metric in the API. An App campaign install IS a
  # conversion action, identified by the configured ID — never by matching the
  # word "install" in a name, which is a label a human can rename at any time.
  #
  # Idempotent: the same day can be synced any number of times. That is what
  # makes the rolling re-sync window safe, and it is required because Google
  # revises attributed conversions for days already reported.
  class AndroidAcquisitionSync
    # Today plus the 7 previous days — 8 dates including today. Retroactive
    # attribution adjustments land inside this window, so re-syncing it every
    # hour makes the cache self-correcting without any backfill machinery.
    DEFAULT_LOOKBACK_DAYS = 7
    MAX_LOOKBACK_DAYS = 365

    Result = Struct.new(
      :status, :start_date, :end_date, :campaign_id, :rows_written,
      :installs, :sign_ups, :installs_all_conversions, :sign_ups_all_conversions,
      :missing, :error,
      keyword_init: true
    ) do
      def ok?
        status == "ok"
      end

      # Reported, never silently applied. metrics.conversions is what the Google
      # Ads UI calls "Conversions" and is what the panel shows; all_conversions
      # additionally counts actions not set to "include in Conversions". A gap
      # between them is information about the account's configuration, not a bug
      # to paper over by switching columns.
      def conversion_column_divergence
        {
          installs: (installs_all_conversions.to_d - installs.to_d).to_f.round(2),
          sign_ups: (sign_ups_all_conversions.to_d - sign_ups.to_d).to_f.round(2)
        }
      end
    end

    class << self
      def campaign_id
        ENV["GOOGLE_ADS_ANDROID_CAMPAIGN_ID"].to_s.gsub(/\D/, "").presence
      end

      def install_conversion_action_id
        ENV["GOOGLE_ADS_INSTALL_CONVERSION_ACTION_ID"].to_s.gsub(/\D/, "").presence
      end

      def signup_conversion_action_id
        ENV["GOOGLE_ADS_SIGNUP_CONVERSION_ACTION_ID"].to_s.gsub(/\D/, "").presence
      end

      def configured?
        Client.configured? && campaign_id.present?
      end

      def missing_configuration
        missing = Client.configured? ? [] : Client.missing_env
        missing << "GOOGLE_ADS_ANDROID_CAMPAIGN_ID" if campaign_id.blank?
        missing
      end
    end

    def initialize(days: DEFAULT_LOOKBACK_DAYS, client: nil, today: nil)
      @days = days.to_i.clamp(0, MAX_LOOKBACK_DAYS)
      @client = client
      @today = today || Analytics::ReportingTime.today
    end

    attr_reader :days

    def call
      unless self.class.configured?
        return Result.new(status: "not_configured", missing: self.class.missing_configuration)
      end

      performance = fetch_performance
      conversions = fetch_conversions
      rows = build_rows(performance, conversions)

      persist(rows)

      Result.new(
        status: "ok",
        start_date: start_date,
        end_date: end_date,
        campaign_id: campaign_id,
        rows_written: rows.size,
        installs: totals(rows, :installs),
        sign_ups: totals(rows, :sign_ups),
        installs_all_conversions: @all_conversions_totals[:installs],
        sign_ups_all_conversions: @all_conversions_totals[:sign_ups]
      )
    end

    def start_date
      @today - days
    end

    def end_date
      @today
    end

    private

    def client
      @client ||= Client.new
    end

    def campaign_id
      self.class.campaign_id
    end

    # Query A — performance. The ONLY source of cost. No conversion segment
    # here, by design.
    def fetch_performance
      client.search(<<~GAQL.squish)
        SELECT campaign.id,
               campaign.name,
               segments.date,
               metrics.impressions,
               metrics.clicks,
               metrics.cost_micros
        FROM campaign
        WHERE campaign.id = #{campaign_id}
          AND segments.date BETWEEN '#{start_date.iso8601}' AND '#{end_date.iso8601}'
      GAQL
    end

    # Query B — conversions by action. Carries no cost column at all, so cost
    # cannot be double counted even by accident.
    def fetch_conversions
      client.search(<<~GAQL.squish)
        SELECT campaign.id,
               campaign.name,
               segments.date,
               segments.conversion_action,
               segments.conversion_action_name,
               metrics.conversions,
               metrics.all_conversions
        FROM campaign
        WHERE campaign.id = #{campaign_id}
          AND segments.date BETWEEN '#{start_date.iso8601}' AND '#{end_date.iso8601}'
      GAQL
    end

    def build_rows(performance, conversions)
      synced_at = Time.current
      by_date = {}

      performance.each do |row|
        date = row.dig("segments", "date")
        next if date.blank?
        next unless same_campaign?(row)

        metrics = row["metrics"] || {}
        by_date[date] = {
          date: Date.parse(date),
          campaign_id: campaign_id,
          campaign_name: row.dig("campaign", "name"),
          impressions: metrics["impressions"].to_i,
          clicks: metrics["clicks"].to_i,
          cost_micros: metrics["costMicros"].to_i,
          installs: 0.to_d,
          sign_ups: 0.to_d,
          synced_at: synced_at
        }
      end

      @all_conversions_totals = { installs: 0.to_d, sign_ups: 0.to_d }

      conversions.each do |row|
        date = row.dig("segments", "date")
        next if date.blank?
        next unless same_campaign?(row)

        kpi = kpi_for(row.dig("segments", "conversionAction"))
        # Any other conversion action of the campaign (a purchase, a custom
        # event) is deliberately ignored for these two KPIs.
        next if kpi.nil?

        entry = by_date[date] ||= {
          date: Date.parse(date),
          campaign_id: campaign_id,
          campaign_name: row.dig("campaign", "name"),
          impressions: 0,
          clicks: 0,
          cost_micros: 0,
          installs: 0.to_d,
          sign_ups: 0.to_d,
          synced_at: synced_at
        }

        metrics = row["metrics"] || {}
        entry[kpi] += metrics["conversions"].to_d
        @all_conversions_totals[kpi] += metrics["allConversions"].to_d
      end

      by_date.values.sort_by { |row| row[:date] }
    end

    # The API filters by campaign already; this is a belt-and-braces guard so a
    # future query change can never blend a second campaign into these rows.
    def same_campaign?(row)
      id = row.dig("campaign", "id").to_s
      id.blank? || id == campaign_id
    end

    # Compares the numeric ID at the end of the resource name
    # ("customers/123/conversionActions/456" => "456"), so a renamed conversion
    # action keeps working.
    def kpi_for(resource_name)
      id = resource_name.to_s.split("/").last.to_s
      return nil if id.blank?

      case id
      when self.class.install_conversion_action_id then :installs
      when self.class.signup_conversion_action_id then :sign_ups
      end
    end

    def persist(rows)
      return if rows.empty?

      GoogleAdsDailyMetric.upsert_all(
        rows,
        unique_by: GoogleAdsDailyMetric::UNIQUE_INDEX,
        record_timestamps: true
      )
    end

    def totals(rows, key)
      rows.sum { |row| row[key] }
    end
  end
end
