namespace :google_ads do
  desc "Sync the Google Ads Android acquisition cache (cron entry point). DAYS=7 by default"
  task sync_android_acquisition: :environment do
    days = ENV["DAYS"].to_s.strip.match?(/\A\d+\z/) ? Integer(ENV["DAYS"]) : nil
    args = days ? { days: days } : {}
    result = GoogleAdsAndroidAcquisitionSyncJob.perform_now(**args)

    puts "\n=== Google Ads — sync aquisição Android ==="

    if result.status == "not_configured"
      puts "  status     : NÃO CONFIGURADO"
      puts "  faltando   : #{result.missing.join(', ')}"
      puts "\n  Rode `rake google_ads:discover` depois de preencher as credenciais OAuth."
      puts ""
      next
    end

    divergence = result.conversion_column_divergence

    puts "  status     : ok"
    puts "  campanha   : #{result.campaign_id}"
    puts "  período    : #{result.start_date} .. #{result.end_date} " \
         "(#{(result.end_date - result.start_date).to_i + 1} datas, hoje incluído)"
    puts "  linhas     : #{result.rows_written}"
    puts "  instalações: #{result.installs.to_f}"
    puts "  sign_up    : #{result.sign_ups.to_f}"
    puts ""
    # all_conversions is reported, never substituted: a gap means the account
    # has actions outside "Conversions", which is a configuration fact someone
    # needs to see rather than a column to silently swap.
    puts "  all_conversions x conversions (diagnóstico, não usado nos KPIs):"
    puts "    instalações: +#{divergence[:installs]}"
    puts "    sign_up    : +#{divergence[:sign_ups]}"
    puts ""
  end

  desc "List Google Ads campaigns and conversion actions so the real IDs can be put in the env"
  task discover: :environment do
    unless GoogleAds::Client.configured?
      puts "\nGoogle Ads não configurado. Faltando: #{GoogleAds::Client.missing_env.join(', ')}\n\n"
      next
    end

    discovery = GoogleAds::Discovery.new

    puts "\n=== Campanhas ==="
    puts "  (* = App campaign ou app_id contendo #{GoogleAds::Discovery::ANDROID_PACKAGE})"
    puts format("  %-2s %-12s %-34s %-10s %-14s %-18s %-26s %s",
                "", "ID", "NOME", "STATUS", "CHANNEL", "SUB_TYPE", "APP_ID", "STORE")

    discovery.campaigns.each do |row|
      puts format("  %-2s %-12s %-34s %-10s %-14s %-18s %-26s %s",
                  row[:highlight] ? "*" : "",
                  row[:id],
                  row[:name].to_s.truncate(34),
                  row[:status],
                  row[:channel_type],
                  row[:channel_sub_type],
                  row[:app_id].to_s.truncate(26),
                  row[:app_store])
    end

    puts "\n=== Conversion actions ==="
    puts format("  %-12s %-46s %-10s %-28s %-22s %-14s %s",
                "ID", "NOME", "STATUS", "TYPE", "CATEGORY", "ORIGIN", "PRIMARY")

    discovery.conversion_actions.each do |row|
      puts format("  %-12s %-46s %-10s %-28s %-22s %-14s %s",
                  row[:id],
                  row[:name].to_s.truncate(46),
                  row[:status],
                  row[:type],
                  row[:category],
                  row[:origin],
                  row[:primary_for_goal] ? "sim" : "não")
    end

    puts <<~HELP

      Nada aqui é escolhido automaticamente: nome de campanha e de conversão são
      rótulos editáveis no painel do Google Ads. Escolha os IDs olhando a lista e
      preencha no .env do servidor:

        GOOGLE_ADS_ANDROID_CAMPAIGN_ID=<id da campanha Android ATUAL>
        GOOGLE_ADS_INSTALL_CONVERSION_ACTION_ID=<id da conversão de instalação>
        GOOGLE_ADS_SIGNUP_CONVERSION_ACTION_ID=<id da conversão sign_up>

    HELP
  end
end
