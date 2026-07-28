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
    # Sinais observados, nunca app_build: o shell Android carrega o bundle web
    # remoto, então o build não diz se o vínculo podia acontecer.
    puts "RECONCILIAÇÃO (sinais observados)"
    r = m[:reconciliation]
    puts "  sinal autenticado:            #{r[:observed_authenticated_installations]}"
    puts "  vinculadas atualmente:        #{r[:linked_installations]}"
    puts "  não vinculadas:               #{r[:authenticated_unlinked_installations]}"
    puts "  vínculos do fluxo novo:       #{r[:new_flow_linked_installations]}"
    puts "  vínculos legados observados:  #{r[:legacy_linked_observed_installations]}"
    puts "  tentativas de vínculo:        #{r[:link_attempted_installations]}"
    puts "  conflitos:                    #{r[:conflicts]}"
    puts "  taxa operacional (user_id):   #{pct.call(r[:link_rate])}"
    if r[:failures_by_code].any?
      puts "  falhas por código:"
      r[:failures_by_code].each { |code, count| puts "    #{code.to_s.ljust(28)}#{count}" }
    else
      puts "  falhas por código:            nenhuma"
    end
    puts "  nota: #{m[:definitions][:linked_at_note]}"
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
