namespace :mobile_tracking do
  desc "READ-ONLY report of historical device_token candidates. Writes no app_installations/user links."
  task backfill_installations: :environment do
    report = MobileTracking::BackfillInstallations.new(dry_run: true).call

    puts "[mobile_tracking:backfill_installations] READ ONLY (no writes)"
    puts "  device_tokens scanned:          #{report.device_tokens_scanned}"
    puts "  app_installations candidates:   #{report.installations_created}"
    puts "  app_installations existing:     #{report.installations_existing}"
    puts "  activation_platform candidates: #{report.activation_platform_backfilled}"
    puts ""
    puts "  Historical writes are disabled: link repair depends on X-Installation-Id observed in authenticated requests."
  end

  desc "READ-ONLY report of the Android installation metrics shown in the admin panel. " \
       "Writes nothing and prints no installation_id, e-mail or user id."
  task installation_metrics: :environment do
    m = Analytics::AndroidInstallations.new.call
    min_build = m[:definitions][:reconciliation_min_build]

    pct = ->(metric) { metric.denominator.zero? ? "—" : "#{metric.value}% (#{metric.numerator}/#{metric.denominator})" }

    puts "[mobile_tracking:installation_metrics] #{m[:generated_at]} · fonte: #{m[:source]} (READ-ONLY)"
    puts ""
    puts "HISTÓRICO (todas as instalações Android)"
    o = m[:overview]
    puts "  instalações registradas:      #{o[:total_installations]}"
    puts "  vinculadas:                   #{o[:linked_installations]}"
    puts "  ainda anônimas:               #{o[:anonymous_installations]}"
    puts "  autenticadas (com carimbo):   #{o[:authenticated_installations]}"
    puts "  usuários Android únicos:      #{o[:unique_linked_users]}"
    puts "  usuários com 2+ instalações:  #{o[:users_with_multiple_installations]}"
    puts "  ativas 7d / 30d:              #{o[:active_installations_7d]} / #{o[:active_installations_30d]}"
    puts "  taxa de vínculo:              #{pct.call(o[:link_rate])}"
    puts ""
    puts "TRACKING ATUAL (build #{min_build}+)"
    c = m[:current_tracking]
    puts "  instalações:                  #{c[:total_installations]}"
    puts "  vinculadas / anônimas:        #{c[:linked_installations]} / #{c[:anonymous_installations]}"
    puts "  taxa de vínculo:              #{pct.call(c[:link_rate])}"
    puts ""
    puts "LEGADO (antes do build #{min_build})"
    l = m[:legacy]
    puts "  instalações:                  #{l[:total_installations]}"
    puts "  vinculadas / anônimas:        #{l[:linked_installations]} / #{l[:anonymous_installations]}"
    puts ""
    puts "QUALIDADE DOS DADOS"
    if m[:data_quality].values.all?(&:zero?)
      puts "  nenhuma inconsistência detectada"
    else
      m[:data_quality].each { |key, value| puts "  #{key.to_s.ljust(30)}#{value}" }
    end
    puts ""
    puts "ADOÇÃO DE VERSÃO"
    a = m[:adoption]
    puts "  versão mais usada:            #{a[:most_used_version] || '—'} (#{a[:most_used_version_installations]})"
    puts "  build mais usado:             #{a[:most_used_build] || '—'} (#{a[:most_used_build_installations]})"
    puts "  último build conhecido:       #{a[:latest_build] || '—'}"
    puts "  no build mais recente:        #{pct.call(a[:latest_build_share])}"
    puts ""
    puts "VERSÕES MAIS USADAS"
    m[:versions].first(10).each do |v|
      label = "#{v[:app_version] || 'sem versão'} (build #{v[:app_build] || 'não informado'})"
      puts "  #{label.ljust(34)}#{v[:total_installations]} inst · #{pct.call(v[:link_rate])} vinculadas"
    end
    puts ""
    puts "SAÚDE OPERACIONAL"
    m[:operational_health].each { |comp| puts "  [#{comp[:status].upcase.ljust(9)}] #{comp[:label]} — #{comp[:detail]}" }
  end
end
