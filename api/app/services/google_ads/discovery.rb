module GoogleAds
  # Read-only listing of campaigns and conversion actions, so the real IDs can
  # be put into the env.
  #
  # DISCOVERY ONLY — it never picks anything. Names like "sign_up" or
  # "Instalações" are labels a human can rename in the Google Ads UI at any
  # moment; auto-selecting on them would silently re-point a KPI. App campaigns
  # for the configured package are flagged and sorted first purely to make them
  # easy to find in the output.
  class Discovery
    ANDROID_PACKAGE = "com.EasyHealth.myapp".freeze
    APP_CAMPAIGN = "APP_CAMPAIGN".freeze

    def initialize(client: nil)
      @client = client
    end

    def campaigns
      rows = client.search(<<~GAQL.squish)
        SELECT campaign.id,
               campaign.name,
               campaign.status,
               campaign.advertising_channel_type,
               campaign.advertising_channel_sub_type,
               campaign.app_campaign_setting.app_id,
               campaign.app_campaign_setting.app_store
        FROM campaign
        ORDER BY campaign.id
      GAQL

      mapped = rows.map do |row|
        campaign = row["campaign"] || {}
        setting = campaign["appCampaignSetting"] || {}

        {
          id: campaign["id"].to_s,
          name: campaign["name"],
          status: campaign["status"],
          channel_type: campaign["advertisingChannelType"],
          channel_sub_type: campaign["advertisingChannelSubType"],
          app_id: setting["appId"],
          app_store: setting["appStore"]
        }
      end

      mapped.each { |row| row[:highlight] = highlight_campaign?(row) }
      # Highlighted first, then newest campaign id first: the campaign created
      # most recently is the one most likely being looked for, but the older one
      # stays listed instead of being filtered away.
      mapped.sort_by { |row| [ row[:highlight] ? 0 : 1, -row[:id].to_i ] }
    end

    def conversion_actions
      rows = client.search(<<~GAQL.squish)
        SELECT conversion_action.id,
               conversion_action.name,
               conversion_action.status,
               conversion_action.type,
               conversion_action.category,
               conversion_action.origin,
               conversion_action.primary_for_goal
        FROM conversion_action
        ORDER BY conversion_action.id
      GAQL

      rows.map do |row|
        action = row["conversionAction"] || {}

        {
          id: action["id"].to_s,
          name: action["name"],
          status: action["status"],
          type: action["type"],
          category: action["category"],
          origin: action["origin"],
          primary_for_goal: action["primaryForGoal"]
        }
      end
    end

    private

    def client
      @client ||= Client.new
    end

    def highlight_campaign?(row)
      row[:channel_type].to_s == APP_CAMPAIGN ||
        row[:app_id].to_s.include?(ANDROID_PACKAGE)
    end
  end
end
