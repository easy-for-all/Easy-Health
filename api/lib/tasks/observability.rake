namespace :observability do
  desc "Run every health check, persist results and reconcile incidents (cron entry point)"
  task check: :environment do
    Observability::Context.for_task("observability_health_check") do
      summary = ObservabilityHealthCheckJob.perform_now

      puts "\n=== Observability check ==="
      puts "  checks     : #{summary.results.size}"
      puts "  duração    : #{summary.duration_ms}ms"
      puts "  abertos    : #{summary.incidents_opened}"
      puts "  resolvidos : #{summary.incidents_resolved}"
      puts ""

      summary.results.sort_by { |r| Observability::CheckResult::SEVERITY_ORDER.index(r.status) || 99 }.each do |result|
        puts "  [#{result.status.ljust(18)}] #{result.check_key}"
        puts "      #{result.explanation}"
      end
      puts ""
    end
  end

  desc "Show the latest status of every check"
  task status: :environment do
    results = ObservabilityCheckResult.latest_per_check.to_a

    if results.empty?
      puts "\nNenhum check executado ainda. Rode: rake observability:check\n\n"
      next
    end

    puts "\n=== Último status por check ==="
    results.sort_by { |r| r.check_key }.each do |result|
      value = result.current_value.nil? ? "sem medição" : result.current_value.to_f.to_s
      puts "  [#{result.status.ljust(18)}] #{result.check_key.ljust(42)} valor=#{value} amostra=#{result.sample_size || '-'}"
      puts "      #{result.explanation}"
    end
    puts ""
  end

  desc "Register every known heartbeat and show its current state"
  task heartbeats: :environment do
    Observability::Heartbeat.register_all!

    puts "\n=== Heartbeats ==="
    ObservabilityHeartbeat.order(:key).each do |hb|
      json = hb.as_observability_json
      puts "  [#{json[:status].ljust(18)}] #{hb.key.ljust(32)} categoria=#{hb.category.ljust(12)} " \
           "último sucesso=#{json[:last_succeeded_at] || 'nunca'} falhas=#{hb.consecutive_failures}"
    end
    puts ""
  end

  desc "List open and acknowledged incidents"
  task open_incidents: :environment do
    incidents = ObservabilityIncident.active.recent_first.to_a

    if incidents.empty?
      puts "\nNenhum incidente aberto.\n\n"
      next
    end

    puts "\n=== Incidentes ativos (#{incidents.size}) ==="
    incidents.each do |incident|
      puts "  ##{incident.id} [#{incident.severity.upcase}] #{incident.title}"
      puts "      status=#{incident.status} ocorrências=#{incident.occurrence_count} " \
           "desde=#{incident.first_detected_at.iso8601}"
      puts "      #{incident.description}"
    end
    puts ""
  end

  desc "Resolve incidents whose check has been healthy for a while and prune old check results"
  task resolve_stale: :environment do
    Observability::Context.for_task("observability_resolve_stale") do
      grace_hours = Integer(ENV.fetch("STALE_INCIDENT_HOURS", "24"), exception: false) || 24
      cutoff = grace_hours.hours.ago

      # An incident whose check has not re-detected it in `grace_hours` is over:
      # the runner resolves on an explicit healthy result, but a check that
      # stops being emitted at all (a cohort that no longer exists, a heartbeat
      # that was removed) would otherwise leave the incident open forever.
      stale = ObservabilityIncident.active.where(last_detected_at: ..cutoff)
      resolved = stale.count
      stale.find_each { |incident| Observability::IncidentManager.resolve!(incident, resolved_by: "stale_timeout") }

      retention_days = Observability::Config.check_retention_days
      deleted = ObservabilityCheckResult.where(checked_at: ...retention_days.days.ago).delete_all

      puts "\n=== Limpeza ==="
      puts "  incidentes resolvidos por inatividade (> #{grace_hours}h): #{resolved}"
      puts "  check_results removidos (> #{retention_days} dias)        : #{deleted}"
      puts ""
    end
  end

  desc "Send a synthetic alert to the configured webhook (guarded in production)"
  task test_alert: :environment do
    if Rails.env.production? && !ActiveModel::Type::Boolean.new.cast(ENV["CONFIRM_PRODUCTION_ALERT_TEST"])
      abort "Recusando enviar alerta de teste em produção sem CONFIRM_PRODUCTION_ALERT_TEST=true"
    end

    unless Observability::Config.alerts_enabled?
      puts "\nOBSERVABILITY_ALERTS_ENABLED está desligado — nada seria enviado."
      puts "Defina OBSERVABILITY_ALERTS_ENABLED=true e OBSERVABILITY_ALERT_WEBHOOK_URL para testar.\n\n"
      next
    end

    # Built in memory and never persisted: a test must not pollute the incident
    # table the panel reads from.
    incident = ObservabilityIncident.new(
      id: 0,
      fingerprint: "test",
      source: "manual",
      check_key: "observability_test_alert",
      title: "Alerta de teste",
      description: "Disparado manualmente por rake observability:test_alert.",
      severity: "warning",
      status: ObservabilityIncident::STATUS_OPEN,
      dimensions: {},
      first_detected_at: Time.current,
      last_detected_at: Time.current,
      occurrence_count: 1,
      metadata: {}
    )

    delivered = Observability::Notifier.deliver(incident: incident, event: "observability_incident_opened")

    puts "\n=== Teste de alerta ==="
    puts "  entregue: #{delivered}"
    puts "  destino : #{Observability::Config.alert_webhook_url.to_s.sub(%r{(://[^/]+).*}, '\\1/...')}"
    puts ""
  end

  namespace :bi_views do
    desc "Create or replace every bi_observability_* view (idempotent)"
    task apply: :environment do
      applied = Observability::BiViews.apply!
      puts "\n=== Views BI aplicadas ==="
      applied.each { |name| puts "  #{name}" }
      puts ""
    end

    desc "Show which bi_observability_* views exist in the current database"
    task verify: :environment do
      present = Observability::BiViews.verify!
      expected = Observability::BiViews.view_names

      puts "\n=== Views BI ==="
      expected.each do |name|
        puts "  [#{present.include?(name) ? 'ok    ' : 'AUSENTE'}] #{name}"
      end
      puts ""
      abort "Views ausentes — rode: rake observability:bi_views:apply" unless (expected - present).empty?
    end

    desc "Drop every bi_observability_* view"
    task drop: :environment do
      dropped = Observability::BiViews.drop!
      puts "\nViews removidas: #{dropped.join(', ')}\n\n"
    end
  end
end
