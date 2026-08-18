module Observability
  module Checks
    # PRIORITY 4 — "something stopped running and nobody noticed".
    #
    # The hardest class of failure in this app, because most recurring work runs
    # in cron/rake processes outside Puma: nothing raises, nothing 500s, the
    # dashboards stay green and the work simply stops. Every sub-check here is
    # about ABSENCE rather than errors.
    #
    # Sub-checks emitted:
    #   stale_heartbeat                 (one per registered process)
    #   repeated_job_failure
    #   make_delivery_backlog
    #   make_processing_unknown_backlog
    #   stripe_webhook_failure
    #   replica_refresh_stale
    #   android_analytics_ingestion_stale
    class JobsIntegrationsCheck < BaseCheck
      CHECK_KEY = "stale_heartbeat".freeze

      def self.check_key = CHECK_KEY

      def call
        heartbeat_results +
          [ repeated_failure_result, make_backlog_result, make_processing_unknown_result, stripe_failure_result,
            replica_result, analytics_ingestion_result ]
      end

      private

      def heartbeats
        @heartbeats ||= ObservabilityHeartbeat.all.to_a
      end

      # The BI replica gets its own dedicated result (with a schedule-aware
      # window), so it is excluded here to avoid alerting twice on one fact.
      def heartbeat_results
        tracked = heartbeats.reject { |hb| hb.key == "bi_replica_refresh" }
        return [] if tracked.empty?

        tracked.map { |hb| heartbeat_result(hb) }
      end

      def heartbeat_result(heartbeat)
        status = heartbeat.status(now: now)
        elapsed = heartbeat.seconds_since_success(now: now)
        interval = heartbeat.expected_interval_seconds

        explanation =
          case status
          when ObservabilityHeartbeat::STATUS_PENDING
            "Processo '#{heartbeat.key}' registrado mas ainda sem execução bem-sucedida, " \
            "dentro do primeiro intervalo esperado. Sem conclusão possível ainda."
          when ObservabilityHeartbeat::STATUS_HEALTHY
            "Último sucesso há #{humanize(elapsed)} (esperado a cada #{humanize(interval)})."
          else
            "Sem sucesso há #{humanize(elapsed)}, contra intervalo esperado de #{humanize(interval)}."
          end

        Observability::CheckResult.new(
          check_key: "#{CHECK_KEY}:#{heartbeat.key}",
          status: status,
          current_value: elapsed,
          reference_value: interval,
          threshold_value: (interval * config.heartbeat_warning_multiplier).round,
          sample_size: elapsed.nil? ? nil : 1,
          unit: "seconds",
          dimensions: { "heartbeat_key" => heartbeat.key, "category" => heartbeat.category },
          explanation: explanation,
          definition: "segundos desde o último sucesso vs intervalo esperado (#{config.heartbeat_warning_multiplier}x aviso, #{config.heartbeat_critical_multiplier}x crítico)",
          window_ended_at: now
        )
      end

      def repeated_failure_result
        worst = heartbeats.max_by { |hb| hb.consecutive_failures.to_i }
        failures = worst&.consecutive_failures.to_i

        status =
          if failures >= config.job_failure_critical_streak
            Observability::CheckResult::CRITICAL
          elsif failures >= config.job_failure_warning_streak
            Observability::CheckResult::WARNING
          else
            Observability::CheckResult::HEALTHY
          end

        # The wording follows the verdict, not the raw number: a count below the
        # warning streak is normal noise and must not read like an alert.
        explanation =
          if failures.zero?
            "Nenhum processo com falhas consecutivas."
          elsif status == Observability::CheckResult::HEALTHY
            "'#{worst.key}' com #{failures} falha(s) consecutiva(s), abaixo do limite de " \
            "#{config.job_failure_warning_streak}. Dentro do normal."
          else
            "'#{worst.key}' acumula #{failures} falha(s) consecutiva(s) (último código: #{worst.last_error_code || 'n/d'})."
          end

        Observability::CheckResult.new(
          check_key: "repeated_job_failure",
          status: status,
          current_value: failures,
          threshold_value: config.job_failure_warning_streak,
          sample_size: heartbeats.size,
          unit: "count",
          dimensions: { "heartbeat_key" => worst&.key }.compact,
          explanation: explanation,
          definition: "maior número de falhas consecutivas entre os processos monitorados",
          window_ended_at: now
        )
      end

      # Counts events STUCK, not events failed. An empty queue with nothing to
      # send is healthy, and an age floor keeps the :async adapter's normal
      # deploy-time losses from firing this every release.
      def make_backlog_result
        age = config.make_backlog_age_minutes
        cutoff = now - age.minutes
        stale_sending_cutoff = now - MakePendingDeliveryRetry::STALE_SENDING_AFTER
        terminal_ids = MakePendingDeliveryRetry.terminal_relationship_user_event_ids
        stale_sending = UserEvent.where(make_delivery_status: "sending").where(make_last_attempt_at: ..stale_sending_cutoff)

        counts = {
          pending: UserEvent.pending_make_delivery.where(created_at: ..cutoff).where.not(id: terminal_ids).count,
          retrying_due: UserEvent.where(make_delivery_status: "retrying").where(make_next_retry_at: ..now).where.not(id: terminal_ids).count,
          sending_stale: stale_sending.where.not(id: terminal_ids).count,
          sending_terminal_pending_reconciliation: stale_sending.where(id: terminal_ids).count
        }
        stuck = counts.except(:sending_terminal_pending_reconciliation).values.sum

        status =
          if stuck >= config.make_backlog_critical
            Observability::CheckResult::CRITICAL
          elsif stuck >= config.make_backlog_warning
            Observability::CheckResult::WARNING
          else
            Observability::CheckResult::HEALTHY
          end

        explanation =
          if stuck.zero?
            "Nenhum evento pendente/retrying/sending preso."
          elsif status == Observability::CheckResult::HEALTHY
            "#{stuck} evento(s) Make preso(s), abaixo do limite de " \
            "#{config.make_backlog_warning}. Backlog normal."
          else
            "#{stuck} evento(s) aguardando entrega ao Make. " \
            "pending=#{counts[:pending]}, retrying_due=#{counts[:retrying_due]}, " \
            "sending_stale=#{counts[:sending_stale]}, " \
            "sending_terminal_pending_reconciliation=#{counts[:sending_terminal_pending_reconciliation]}. " \
            "Remediação: bin/rails orchestration:retry_pending_make."
          end

        Observability::CheckResult.new(
          check_key: "make_delivery_backlog",
          status: status,
          current_value: stuck,
          threshold_value: config.make_backlog_warning,
          sample_size: stuck,
          unit: "count",
          dimensions: counts,
          explanation: explanation,
          definition: "user_events pending há mais de #{age} min, retrying vencidos " \
                      "ou sending sem relationship_message terminal há mais de #{MakePendingDeliveryRetry::STALE_SENDING_AFTER.inspect}",
          window_ended_at: now
        )
      end

      def make_processing_unknown_result
        age = config.make_backlog_age_minutes
        cutoff = now - age.minutes
        stale = UserEvent
                .where(make_delivery_status: "accepted_by_make", make_processing_status: "unknown")
                .where(created_at: ..cutoff)
                .count

        status =
          if stale >= config.make_backlog_critical
            Observability::CheckResult::CRITICAL
          elsif stale >= config.make_backlog_warning
            Observability::CheckResult::WARNING
          else
            Observability::CheckResult::HEALTHY
          end

        explanation =
          if stale.zero?
            "Nenhum evento aceito pelo Make aguardando processamento há mais de #{age} min."
          elsif status == Observability::CheckResult::HEALTHY
            "#{stale} evento(s) aceito(s) pelo Make ainda com processamento unknown, abaixo do limite de " \
            "#{config.make_backlog_warning}."
          else
            "#{stale} evento(s) accepted_by_make ainda com make_processing_status=unknown há mais de #{age} min. " \
            "Verifique callbacks do Make e relacionamento com relationship_messages."
          end

        Observability::CheckResult.new(
          check_key: "make_processing_unknown_backlog",
          status: status,
          current_value: stale,
          threshold_value: config.make_backlog_warning,
          sample_size: stale,
          unit: "count",
          explanation: explanation,
          definition: "user_events accepted_by_make com make_processing_status='unknown' criados há mais de #{age} min",
          window_ended_at: now
        )
      end

      def stripe_failure_result
        cutoff = now - 1.hour
        failed = StripeEvent.where.not(status: "processed").where(created_at: cutoff..).count

        status =
          if failed >= config.stripe_failure_critical
            Observability::CheckResult::CRITICAL
          elsif failed >= config.stripe_failure_warning
            Observability::CheckResult::WARNING
          else
            Observability::CheckResult::HEALTHY
          end

        Observability::CheckResult.new(
          check_key: "stripe_webhook_failure",
          status: status,
          current_value: failed,
          threshold_value: config.stripe_failure_warning,
          sample_size: failed,
          unit: "count",
          explanation: failed.positive? ? "#{failed} webhook(s) Stripe não processado(s) na última hora." : "Nenhum webhook Stripe pendente na última hora.",
          definition: "stripe_events com status <> 'processed' criados na última hora",
          window_started_at: cutoff,
          window_ended_at: now
        )
      end

      # Schedule-aware. The crontab that actually drives the refresh lives on the
      # VPS and is NOT knowable from this repo (install_cron.sh only supplies a
      # default), so the expected hour is configuration, not a constant. Before
      # expected_hour + grace has passed today, "no refresh yet" is simply not
      # yet news.
      def replica_result
        heartbeat = heartbeats.find { |hb| hb.key == "bi_replica_refresh" }
        zone = Analytics::ReportingTime.zone
        local_now = now.in_time_zone(zone)
        deadline = local_now.change(hour: config.bi_replica_expected_hour, min: 0) + config.bi_replica_grace_minutes.minutes

        if local_now < deadline
          return insufficient(
            "replica_refresh_stale",
            sample_size: nil,
            definition: replica_definition,
            explanation: "Ainda dentro da janela esperada (limite hoje: #{deadline.strftime('%H:%M')} #{zone}). " \
                         "Sem conclusão possível antes disso."
          )
        end

        last_success = heartbeat&.last_succeeded_at

        if last_success.nil?
          return Observability::CheckResult.new(
            check_key: "replica_refresh_stale",
            status: Observability::CheckResult::CRITICAL,
            threshold_value: 0,
            unit: "seconds",
            explanation: "Nenhum refresh bem-sucedido registrado. Verifique 'crontab -l' na VPS e " \
                         "se EASYHEALTH_COMPOSE_FILE está correto no env file.",
            definition: replica_definition,
            window_ended_at: now
          )
        end

        stale = last_success.in_time_zone(zone) < local_now.beginning_of_day
        elapsed = (now - last_success).to_i

        Observability::CheckResult.new(
          check_key: "replica_refresh_stale",
          status: stale ? Observability::CheckResult::CRITICAL : Observability::CheckResult::HEALTHY,
          current_value: elapsed,
          threshold_value: 86_400,
          sample_size: 1,
          unit: "seconds",
          explanation: stale ? "Último refresh da réplica foi antes de hoje (há #{humanize(elapsed)})." : "Réplica atualizada há #{humanize(elapsed)}.",
          definition: replica_definition,
          window_ended_at: now
        )
      end

      def replica_definition
        "último sucesso do heartbeat bi_replica_refresh, avaliado após #{format('%02d:00', config.bi_replica_expected_hour)} " \
        "+ #{config.bi_replica_grace_minutes} min no fuso de produção"
      end

      # Absence of events only means something when there was traffic to produce
      # them. Below the trailing traffic floor this reports insufficient_data —
      # a low-traffic night must not read as a broken pipeline.
      def analytics_ingestion_result
        hours = config.analytics_ingestion_window_hours
        window_start = now - hours.hours

        recent = ProductAnalyticsEvent
                 .where(platform: "android", occurred_at: window_start..now)
                 .count

        baseline_days = 7
        baseline_total = ProductAnalyticsEvent
                         .where(platform: "android", occurred_at: (now - baseline_days.days)..window_start)
                         .count
        baseline_per_hour = baseline_total.to_f / (baseline_days * 24)

        # Corroborating signal: were there installs/sessions that SHOULD have
        # produced events? Without this, "no events" and "no users" are
        # indistinguishable.
        active_installs = AppInstallation
                          .where(platform: "android")
                          .where(last_seen_at: window_start..now)
                          .count

        if baseline_per_hour < config.analytics_ingestion_traffic_floor
          return insufficient(
            "android_analytics_ingestion_stale",
            sample_size: recent,
            definition: ingestion_definition,
            explanation: "Volume médio de #{baseline_per_hour.round(1)} evento(s)/hora nos últimos #{baseline_days} dias " \
                         "está abaixo do piso de tráfego (#{config.analytics_ingestion_traffic_floor}). " \
                         "Ausência de eventos não é conclusiva neste volume."
          )
        end

        status =
          if recent.zero? && active_installs.positive?
            Observability::CheckResult::CRITICAL
          elsif recent.zero?
            Observability::CheckResult::WARNING
          else
            Observability::CheckResult::HEALTHY
          end

        explanation =
          if recent.zero? && active_installs.positive?
            "Nenhum evento Android em #{hours}h, mas #{active_installs} instalação(ões) estiveram ativas no período — " \
            "a ingestão parou."
          elsif recent.zero?
            "Nenhum evento Android em #{hours}h e nenhuma instalação ativa. Provavelmente ausência de tráfego."
          else
            "#{recent} evento(s) Android nas últimas #{hours}h."
          end

        Observability::CheckResult.new(
          check_key: "android_analytics_ingestion_stale",
          status: status,
          current_value: recent,
          reference_value: (baseline_per_hour * hours).round(1),
          threshold_value: 1,
          sample_size: recent,
          unit: "count",
          dimensions: { "active_installations" => active_installs },
          explanation: explanation,
          definition: ingestion_definition,
          window_started_at: window_start,
          window_ended_at: now
        )
      end

      def ingestion_definition
        "eventos Android por occurred_at nas últimas #{config.analytics_ingestion_window_hours}h, " \
        "cruzados com instalações ativas no mesmo período"
      end

      def humanize(seconds)
        return "n/d" if seconds.nil?

        value = seconds.to_i
        return "#{value}s" if value < 60
        return "#{value / 60}min" if value < 3_600
        return "#{(value / 3_600.0).round(1)}h" if value < 86_400

        "#{(value / 86_400.0).round(1)}d"
      end
    end
  end
end
