module Observability
  # Builds the admin observability payload.
  #
  # Reads only PERSISTED check results — it never re-runs a check. The panel
  # must be cheap to open and must show the same numbers the incidents were
  # opened from; recomputing on request would make the panel and the alerts
  # disagree, and would put aggregate queries on a web request.
  #
  # Contract: `cards` has EXACTLY six keys, in a frozen order. A spec asserts it.
  class Dashboard
    CARD_ORDER = %i[
      api_infrastructure
      android_registration
      android_linkage
      google_auth
      jobs_integrations
      open_incidents
    ].freeze

    # Which persisted check keys roll up into which card.
    CARD_CHECKS = {
      api_infrastructure: %w[api_error_rate api_latency_p95],
      android_registration: %w[android_registration_conversion],
      android_linkage: %w[android_installation_link_rate authenticated_without_installation_link],
      google_auth: %w[google_auth_error_rate google_auth_consent_anomaly],
      jobs_integrations: %w[
        repeated_job_failure make_delivery_backlog stripe_webhook_failure
        replica_refresh_stale android_analytics_ingestion_stale
      ]
    }.freeze

    CARD_TITLES = {
      api_infrastructure: "API & Infraestrutura",
      android_registration: "Cadastro Android",
      android_linkage: "Vínculo Android",
      google_auth: "Login Google",
      jobs_integrations: "Jobs e Integrações",
      open_incidents: "Incidentes Abertos"
    }.freeze

    SECONDS_CHECK_KEYS = %w[
      api_latency_p95
      replica_refresh_stale
    ].freeze

    COUNT_CHECK_KEYS = %w[
      authenticated_without_installation_link
      google_auth_consent_anomaly
      repeated_job_failure
      make_delivery_backlog
      stripe_webhook_failure
      android_analytics_ingestion_stale
    ].freeze

    MAX_INCIDENTS = 20

    def initialize(range: "24h")
      @range = %w[24h 7d 30d].include?(range.to_s) ? range.to_s : "24h"
      @now = Time.current
    end

    def call
      {
        generated_at: @now,
        range: @range,
        overall_status: overall_status,
        cards: cards,
        incidents: incidents_payload,
        android_builds: android_builds,
        heartbeats: heartbeats.map { |hb| hb.as_observability_json(now: @now) },
        thresholds: Observability::Config.to_h,
        data_quality: data_quality
      }
    end

    private

    def cards
      @cards ||= CARD_ORDER.index_with { |key| build_card(key) }
    end

    def overall_status
      Observability::CheckResult.worst_status(cards.values.map { |card| card[:status] })
    end

    # Latest persisted result per check, loaded once.
    def latest_results
      @latest_results ||= ObservabilityCheckResult.latest_per_check.to_a
    end

    def results_for(card_key)
      keys = CARD_CHECKS[card_key] || []
      latest_results.select { |result| keys.include?(result.check_key) }
    end

    def heartbeats
      @heartbeats ||= ObservabilityHeartbeat.order(:key).to_a
    end

    def active_incidents
      @active_incidents ||= ObservabilityIncident.active.recent_first.to_a
    end

    def build_card(key)
      return open_incidents_card if key == :open_incidents
      return jobs_card if key == :jobs_integrations

      results = results_for(key)
      return empty_card(key) if results.empty?

      primary = results.max_by { |r| severity_rank(r.status) }
      metrics = results.map { |r| metric_row(r) }

      base_card(key, primary).merge(
        metrics: metrics,
        incident_ids: incident_ids_for(CARD_CHECKS[key])
      )
    end

    def base_card(key, result)
      insufficient = result.status == Observability::CheckResult::INSUFFICIENT

      {
        key: key,
        title: CARD_TITLES[key],
        status: result.status,
        # Never a number when the measurement could not be made: the frontend
        # renders `value: nil` as "amostra insuficiente", never as 0.
        value: insufficient ? nil : result.current_value&.to_f,
        unit: unit_for(result),
        headline: insufficient ? nil : headline_for(result),
        sample_size: result.sample_size,
        reference_value: result.reference_value&.to_f,
        threshold_value: result.threshold_value&.to_f,
        window: {
          started_at: result.window_started_at,
          ended_at: result.window_ended_at,
          label: window_label(result)
        },
        definition: definition_for(result),
        explanation: result.explanation,
        updated_at: result.checked_at
      }
    end

    def metric_row(result)
      insufficient = result.status == Observability::CheckResult::INSUFFICIENT

      {
        check_key: result.check_key,
        status: result.status,
        value: insufficient ? nil : result.current_value&.to_f,
        threshold_value: result.threshold_value&.to_f,
        reference_value: result.reference_value&.to_f,
        sample_size: result.sample_size,
        dimensions: result.dimensions,
        explanation: result.explanation
      }
    end

    # Card 5 mixes check results with live heartbeat counts, because "how many
    # processes are late" is not something a single check result expresses.
    def jobs_card
      results = results_for(:jobs_integrations)
      heartbeat_statuses = heartbeats.map { |hb| hb.status(now: @now) }
      heartbeat_results = latest_results.select { |r| r.check_key.start_with?("stale_heartbeat:") }

      statuses = results.map(&:status) + heartbeat_results.map(&:status)
      status = Observability::CheckResult.worst_status(statuses)

      healthy = heartbeat_statuses.count(ObservabilityHeartbeat::STATUS_HEALTHY)
      late = heartbeat_statuses.count { |s| s.in?([ ObservabilityHeartbeat::STATUS_WARNING, ObservabilityHeartbeat::STATUS_CRITICAL ]) }
      pending = heartbeat_statuses.count(ObservabilityHeartbeat::STATUS_PENDING)
      failing = heartbeats.count { |hb| hb.consecutive_failures.to_i.positive? }

      insufficient = status == Observability::CheckResult::INSUFFICIENT

      {
        key: :jobs_integrations,
        title: CARD_TITLES[:jobs_integrations],
        status: status,
        # The invariant holds here too: when nothing could be concluded, a "0"
        # in the headline slot reads as a measured zero. Suppress it.
        value: insufficient ? nil : healthy,
        unit: "count",
        headline: insufficient ? nil : "#{healthy} saudável(is), #{late} atrasado(s), #{failing} com falha",
        sample_size: heartbeats.size,
        reference_value: nil,
        threshold_value: nil,
        window: { started_at: nil, ended_at: @now, label: "agora" },
        definition: "estado atual dos processos monitorados e das integrações Make, Stripe, réplica e analytics",
        explanation: jobs_explanation(healthy, late, pending, failing),
        updated_at: latest_results.map(&:checked_at).max,
        metrics: (results + heartbeat_results).map { |r| metric_row(r) },
        incident_ids: incident_ids_for(CARD_CHECKS[:jobs_integrations] + heartbeat_results.map(&:check_key))
      }
    end

    def jobs_explanation(healthy, late, pending, failing)
      parts = [ "#{healthy} de #{heartbeats.size} processos com sucesso recente" ]
      parts << "#{late} atrasado(s)" if late.positive?
      parts << "#{pending} ainda sem primeira execução" if pending.positive?
      parts << "#{failing} com falhas consecutivas" if failing.positive?
      "#{parts.join(', ')}."
    end

    def open_incidents_card
      total = active_incidents.size
      critical = active_incidents.count { |i| i.severity == "critical" }
      warning = total - critical
      oldest = active_incidents.min_by(&:first_detected_at)
      newest = active_incidents.max_by(&:first_detected_at)

      status =
        if critical.positive?
          Observability::CheckResult::CRITICAL
        elsif warning.positive?
          Observability::CheckResult::WARNING
        else
          Observability::CheckResult::HEALTHY
        end

      {
        key: :open_incidents,
        title: CARD_TITLES[:open_incidents],
        status: status,
        value: total,
        unit: "count",
        headline: total.zero? ? "Nenhum incidente aberto" : "#{critical} crítico(s), #{warning} aviso(s)",
        sample_size: total,
        reference_value: nil,
        threshold_value: 0,
        window: { started_at: oldest&.first_detected_at, ended_at: @now, label: "agora" },
        definition: "incidentes com status open ou acknowledged",
        explanation: incidents_explanation(total, critical, oldest, newest),
        updated_at: @now,
        metrics: [],
        incident_ids: active_incidents.first(MAX_INCIDENTS).map(&:id),
        oldest_opened_at: oldest&.first_detected_at,
        last_opened_at: newest&.first_detected_at
      }
    end

    def incidents_explanation(total, critical, oldest, newest)
      return "Nenhum incidente aberto no momento." if total.zero?

      parts = [ "#{total} incidente(s) ativo(s)" ]
      parts << "#{critical} crítico(s)" if critical.positive?
      parts << "mais antigo desde #{oldest.first_detected_at.iso8601}" if oldest
      parts << "última abertura em #{newest.first_detected_at.iso8601}" if newest
      "#{parts.join(', ')}."
    end

    # No check has run yet for this card. Explicitly unmeasured — not healthy.
    def empty_card(key)
      {
        key: key,
        title: CARD_TITLES[key],
        status: Observability::CheckResult::INSUFFICIENT,
        value: nil,
        unit: "ratio",
        headline: nil,
        sample_size: nil,
        reference_value: nil,
        threshold_value: nil,
        window: { started_at: nil, ended_at: nil, label: nil },
        definition: nil,
        explanation: "Nenhuma verificação registrada ainda. Rode: rake observability:check",
        updated_at: nil,
        metrics: [],
        incident_ids: []
      }
    end

    def incident_ids_for(check_keys)
      keys = Array(check_keys)
      active_incidents.select { |i| keys.include?(i.check_key) }.map(&:id)
    end

    def incidents_payload
      active_incidents.first(MAX_INCIDENTS).map(&:as_observability_json)
    end

    # Table 2 of the panel. Reads app_installations directly (the honest
    # denominator) and joins the auth outcomes recorded as events.
    def android_builds
      since = range_start

      installs = AppInstallation
                 .where(platform: "android", created_at: since..@now)
                 .group(:app_version, :app_build)
                 .pluck(
                   :app_version, :app_build,
                   Arel.sql("COUNT(*)"),
                   Arel.sql("COUNT(*) FILTER (WHERE last_authenticated_at IS NOT NULL)"),
                   Arel.sql("COUNT(*) FILTER (WHERE user_id IS NOT NULL)")
                 )

      auth_errors = ProductAnalyticsEvent
                    .where(event_name: "google_auth_failed", platform: "android", occurred_at: since..@now)
                    .group(:app_version, :build_number)
                    .count

      registrations = ProductAnalyticsEvent
                      .where(event_name: "android_registration_succeeded", platform: "android", occurred_at: since..@now)
                      .group(:app_version, :build_number)
                      .count

      installs.map do |version, build, total, authenticated, linked|
        key = [ version, build ]
        {
          app_version: version,
          app_build: build,
          build_group: Observability::BuildGroup.for(build),
          installations: total,
          authenticated: authenticated,
          linked: linked,
          anonymous: total - linked,
          registrations: registrations[key].to_i,
          google_auth_errors: auth_errors[key].to_i,
          # NULL, not 0, below the sample floor — the table renders "amostra
          # insuficiente" rather than a percentage it cannot support.
          registration_rate: rate_or_nil(linked, total),
          linkage_rate: rate_or_nil(linked, total),
          sample_size: total,
          status: build_status(linked, total)
        }
      end.sort_by { |row| -row[:installations] }
    end

    def rate_or_nil(numerator, denominator)
      return nil if denominator.to_i < Observability::Config.min_android_sample

      (numerator.to_f / denominator).round(4)
    end

    def build_status(linked, total)
      return Observability::CheckResult::INSUFFICIENT if total.to_i < Observability::Config.min_android_sample

      rate = linked.to_f / total
      return Observability::CheckResult::CRITICAL if rate < Observability::Config.android_link_critical_rate
      return Observability::CheckResult::WARNING if rate < Observability::Config.android_link_warning_rate

      Observability::CheckResult::HEALTHY
    end

    def range_start
      case @range
      when "7d" then @now - 7.days
      when "30d" then @now - 30.days
      else @now - 24.hours
      end
    end

    # Surfaced so the panel can say WHY something is grey instead of leaving the
    # operator to guess whether grey means fine.
    def data_quality
      last_run = latest_results.map(&:checked_at).max
      insufficient = latest_results.count { |r| r.status == Observability::CheckResult::INSUFFICIENT }

      {
        checks_total: latest_results.size,
        insufficient_data: insufficient,
        last_run_at: last_run,
        # 15-minute cadence with a 2x grace before we call the checker itself late.
        stale: last_run.nil? || last_run < @now - 30.minutes,
        notes: data_quality_notes(last_run, insufficient)
      }
    end

    def data_quality_notes(last_run, insufficient)
      notes = []
      notes << "Nenhum ciclo de verificação registrado — rode rake observability:check." if last_run.nil?
      notes << "Última verificação há mais de 30 min; confira o cron de observability:check." if last_run && last_run < @now - 30.minutes
      notes << "#{insufficient} verificação(ões) sem amostra suficiente neste ciclo." if insufficient.positive?
      notes << "Taxa 5xx e p95 vêm de agregação em memória do processo Puma e zeram a cada deploy."
      notes
    end

    def severity_rank(status)
      Observability::CheckResult::SEVERITY_ORDER.reverse.index(status) || 0
    end

    def unit_for(result)
      result_attribute(result, :unit).presence || inferred_unit_for(result_attribute(result, :check_key))
    end

    def definition_for(result)
      result_attribute(result, :definition)
    end

    def result_attribute(result, name)
      return nil if result.respond_to?(:has_attribute?) && !result.has_attribute?(name.to_s)
      return result.public_send(name) if result.respond_to?(name)

      nil
    rescue ActiveModel::MissingAttributeError, NoMethodError
      nil
    end

    def inferred_unit_for(check_key)
      key = check_key.to_s
      return "seconds" if SECONDS_CHECK_KEYS.include?(key) || key.start_with?("stale_heartbeat:")
      return "count" if COUNT_CHECK_KEYS.include?(key)

      "ratio"
    end

    def headline_for(result)
      value = result.current_value
      return nil if value.nil?

      case unit_for(result)
      when "count" then "#{value.to_i}"
      when "seconds" then "#{value.to_f.round(2)}s"
      else format("%.1f%%", value.to_f * 100).tr(".", ",")
      end
    end

    def window_label(result)
      return nil if result.window_started_at.nil? || result.window_ended_at.nil?

      minutes = ((result.window_ended_at - result.window_started_at) / 60).round
      return "últimos #{minutes} min" if minutes < 60
      return "últimas #{(minutes / 60.0).round}h" if minutes < 1440

      "últimos #{(minutes / 1440.0).round}d"
    end
  end
end
