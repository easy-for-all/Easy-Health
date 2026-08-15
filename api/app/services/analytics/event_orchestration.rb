module Analytics
  # "Eventos & Comunicações" — the operational view of the orchestration
  # pipeline:
  #
  #   UserEvent -> Make delivery -> Make decision -> PushDispatch -> provider
  #
  # Observability only. Copy, campaigns and A/B decisions stay in Make; this
  # answers what happened, to how many people, and where it stopped.
  #
  # Every section is a single aggregate query. The event volume is small today,
  # but a panel that degrades as the product grows stops being opened, and a
  # panel nobody opens is the same as no panel.
  class EventOrchestration
    class InvalidRange < StandardError; end

    PERIODS = {
      "24h" => 24.hours,
      "7d" => 7.days,
      "30d" => 30.days
    }.freeze
    DEFAULT_PERIOD = "24h".freeze
    MAX_CUSTOM_RANGE = 180.days
    RECENT_EVENTS_LIMIT = 50

    # Channels the model understands. whatsapp/in_app are listed with zero so
    # the panel is honest about them being possible and unconfigured, rather
    # than implying an integration that does not exist.
    KNOWN_CHANNELS = %w[push email whatsapp in_app].freeze

    PROVIDER_ACCEPTED_STATUSES = PushDispatch::DELIVERED_STATUSES
    PROVIDER_REJECTED_STATUSES = %w[failed].freeze

    # make_last_error wins over make_delivery_status: several causes share
    # status='disabled' and only the error distinguishes them.
    NOT_SENT_REASON_BUCKETS = {
      "event_not_orchestration" => "event_not_orchestration",
      "no_deliverable_channel" => "no_deliverable_channel",
      "make_webhook_disabled_or_unconfigured" => "webhook_disabled",
      "suppressed_by_producer" => "suppressed",
      "user_deleted_or_anonymized" => "user_deleted_or_anonymized",
      "unknown_communication_event" => "unknown_communication_event",
      "communication_event_disabled" => "communication_event_disabled"
    }.freeze

    NOT_SENT_STATUS_BUCKETS = {
      "pending" => "pending",
      "sending" => "pending",
      "retrying" => "retrying",
      "failed_to_reach_make" => "failed",
      "dead_letter" => "dead_letter",
      "skipped" => "skipped",
      "disabled" => "disabled_without_reason"
    }.freeze

    def initialize(period: nil, start_date: nil, end_date: nil)
      @custom = start_date.present? || end_date.present?
      @period = @custom ? nil : (PERIODS.key?(period.to_s) ? period.to_s : DEFAULT_PERIOD)
      @range = build_range(period, start_date, end_date)
    end

    def call
      {
        period: period_payload,
        summary: summary,
        not_sent_breakdown: not_sent_breakdown,
        by_event: by_event,
        candidate_channels: candidate_channels,
        push_dispatch_results: push_dispatch_results,
        by_origin: by_origin,
        schedulers: schedulers,
        recent_events: recent_events,
        warnings: warnings,
        catalog: {
          orchestration_events: orchestration_event_names,
          push_events: safe_push_events,
          analytics_only_events: analytics_only_event_names,
          uncatalogued_events: uncatalogued_event_names
        }
      }
    end

    private

    attr_reader :period, :range

    def build_range(period, start_date, end_date)
      if @custom
        from = parse_date!(start_date, "start")
        to = parse_date!(end_date, "end")
        raise InvalidRange, "start deve ser anterior a end" if from > to
        raise InvalidRange, "intervalo máximo de #{MAX_CUSTOM_RANGE.inspect}" if (to - from) > MAX_CUSTOM_RANGE

        return from.beginning_of_day..to.end_of_day
      end

      duration = PERIODS.fetch(period.to_s, PERIODS.fetch(DEFAULT_PERIOD))
      duration.ago..Time.current
    end

    def parse_date!(value, label)
      raise InvalidRange, "#{label} é obrigatório para período customizado" if value.blank?

      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      raise InvalidRange, "#{label} inválido: use YYYY-MM-DD"
    end

    def period_payload
      { key: period || "custom", from: range.first.iso8601, to: range.last.iso8601 }
    end

    def orchestration_event_names
      @orchestration_event_names ||= begin
        CommunicationEvents.orchestration_event_names
      rescue CommunicationEvents::ConfigError
        []
      end
    end

    def safe_push_events
      CommunicationEvents.push_events
    rescue CommunicationEvents::ConfigError
      []
    end

    def analytics_only_event_names
      @analytics_only_event_names ||= begin
        CommunicationEvents.analytics_only_event_names
      rescue CommunicationEvents::ConfigError
        []
      end
    end

    # Registry events with no decision in either catalog. This is the coverage
    # bug detector: activation_workout_created sat here, invisible, because the
    # panel only ever queried events that were already in the catalog.
    def uncatalogued_event_names
      @uncatalogued_event_names ||= begin
        CommunicationEvents.uncatalogued_event_names
      rescue CommunicationEvents::ConfigError
        []
      end
    end

    # Events the catalog says MUST reach Make. Same scope as before, renamed at
    # the call sites that care; `scope` is kept as the alias every existing
    # section already uses.
    def scope
      @scope ||= UserEvent.where(event_name: orchestration_event_names, created_at: range)
    end
    alias_method :orchestration_scope, :scope

    # Explicitly classified as never-communication. Counted so the panel can say
    # how much volume was excluded ON PURPOSE — it must never read as a failure.
    def analytics_scope
      @analytics_scope ||= UserEvent.where(event_name: analytics_only_event_names, created_at: range)
    end

    # Restricted to the explicit list derived from RelationshipEventTracker::EVENTS,
    # never `where.not(...)` over arbitrary names: event names produced by other
    # subsystems are not this catalog's business and must not raise false criticals.
    def uncatalogued_scope
      @uncatalogued_scope ||= UserEvent.where(event_name: uncatalogued_event_names, created_at: range)
    end

    # --- Funnel -------------------------------------------------------------

    def summary
      @summary ||= begin
        counts = scope.pick(
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE #{UserEvent::SENT_TO_MAKE_SQL})"),
          Arel.sql("COUNT(*) FILTER (WHERE make_delivery_status = 'accepted_by_make')"),
          Arel.sql("COUNT(*) FILTER (WHERE make_delivery_status IN ('#{UserEvent::ERROR_DELIVERY_STATUSES.join("','")}'))"),
          Arel.sql("COUNT(DISTINCT user_id)")
        ) || [ 0, 0, 0, 0, 0 ]

        generated, sent, accepted, failed, unique_users = counts.map(&:to_i)
        dispatch = dispatch_totals

        {
          events_generated: generated,
          sent_to_make: sent,
          accepted_by_make: accepted,
          failed_make: failed,
          unique_users: unique_users,
          push_requested: dispatch[:requested],
          provider_accepted: dispatch[:accepted],
          provider_rejected: dispatch[:rejected],
          push_deferred: dispatch[:deferred],
          push_skipped: dispatch[:skipped],

          # --- Coverage ------------------------------------------------------
          # "182 generated / 33 accepted / 0 errors" looked healthy while an
          # event that should have reached Make was silently parked, because the
          # denominator only ever contained events already in the catalog. These
          # keys make the denominator explicit and separate the three
          # populations: expected, excluded on purpose, and undecided.
          all_events_generated: all_events_generated,
          orchestration_expected: generated,
          orchestration_sent: sent,
          orchestration_not_sent: generated - sent,
          orchestration_coverage_pct: ratio(sent, generated),
          analytics_only_events: analytics_scope.count,
          uncatalogued_events: uncatalogued_scope.count,

          rates: {
            generated_to_sent: ratio(sent, generated),
            sent_to_accepted: ratio(accepted, sent),
            dispatch_to_provider_accepted: ratio(dispatch[:accepted], dispatch[:requested])
          }
        }
      end
    end

    def all_events_generated
      @all_events_generated ||= UserEvent.where(created_at: range).count
    end

    # --- Why an event did not reach Make ------------------------------------
    #
    # Grouped by CAUSE, not by status. Several different causes share
    # make_delivery_status='disabled' and only make_last_error tells them apart;
    # collapsing them would hide event_not_orchestration — the one that means a
    # fact nobody catalogued — inside the same bucket as a user who legitimately
    # withdrew email consent.
    #
    # Covers orchestration events AND uncatalogued ones. Events explicitly
    # classified as never-communication are excluded: they are not failures.
    def not_sent_breakdown
      rows = UserEvent
             .where(created_at: range, event_name: orchestration_event_names + uncatalogued_event_names)
             .not_sent_to_make
             .group(:make_delivery_status, :make_last_error, :event_name)
             .count

      buckets = Hash.new { |hash, key| hash[key] = { reason: key, count: 0, event_names: Set.new } }

      rows.each do |(status, last_error, event_name), count|
        bucket = buckets[not_sent_bucket(status, last_error)]
        bucket[:count] += count
        bucket[:event_names] << event_name
      end

      buckets.values
             .map { |bucket| bucket.merge(event_names: bucket[:event_names].to_a.sort) }
             .sort_by { |bucket| -bucket[:count] }
    end

    def not_sent_bucket(status, last_error)
      NOT_SENT_REASON_BUCKETS[last_error.to_s] ||
        NOT_SENT_STATUS_BUCKETS[status.to_s] ||
        "unknown"
    end

    def ratio(numerator, denominator)
      { numerator: numerator, denominator: denominator,
        value: denominator.to_i.zero? ? nil : (numerator.to_f / denominator).round(4) }
    end

    # --- Per event ----------------------------------------------------------

    def by_event
      rows = scope.group(:event_name).pluck(
        Arel.sql("event_name"),
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(*) FILTER (WHERE #{UserEvent::SENT_TO_MAKE_SQL})"),
        Arel.sql("COUNT(*) FILTER (WHERE make_delivery_status = 'accepted_by_make')"),
        Arel.sql("COUNT(*) FILTER (WHERE make_delivery_status IN ('#{UserEvent::ERROR_DELIVERY_STATUSES.join("','")}'))"),
        Arel.sql("COUNT(*) FILTER (WHERE make_delivery_status = 'disabled')"),
        Arel.sql("COUNT(DISTINCT user_id)"),
        Arel.sql("MAX(created_at)"),
        Arel.sql("MAX(make_first_attempt_at)")
      )

      dispatch = dispatch_counts_by_event

      rows.map do |name, generated, sent, accepted, failed, disabled, users, last_generated, last_sent|
        counts = dispatch.fetch(name, {})
        {
          event_name: name,
          candidate_channels: channels_for(name),
          generated: generated.to_i,
          sent_to_make: sent.to_i,
          accepted_by_make: accepted.to_i,
          failed_make: failed.to_i,
          disabled: disabled.to_i,
          push_requested: counts[:requested].to_i,
          provider_accepted: counts[:accepted].to_i,
          provider_rejected: counts[:rejected].to_i,
          push_deferred: counts[:deferred].to_i,
          push_skipped: counts[:skipped].to_i,
          unique_users: users.to_i,
          last_generated_at: last_generated&.iso8601,
          last_sent_to_make_at: last_sent&.iso8601
        }
      end.sort_by { |row| -row[:generated] }
    end

    def channels_for(event_name)
      CommunicationEvents.channels_for(event_name)
    rescue CommunicationEvents::ConfigError
      []
    end

    # --- Candidate channels -------------------------------------------------

    # CANDIDATE, not sent. An event routed to push+email counts once for each,
    # even if Make chose to send only one of them. Sending is measured in
    # push_dispatch_results; conflating the two would report intent as delivery.
    def candidate_channels
      per_event = scope.group(:event_name).pluck(
        Arel.sql("event_name"), Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT user_id)"),
        Arel.sql("COUNT(*) FILTER (WHERE #{UserEvent::SENT_TO_MAKE_SQL})")
      )

      totals = KNOWN_CHANNELS.index_with { { candidate_events: 0, sent_to_make: 0, users: Set.new } }

      per_event.each do |name, generated, _users, sent|
        channels_for(name).each do |channel|
          next unless totals.key?(channel)

          totals[channel][:candidate_events] += generated.to_i
          totals[channel][:sent_to_make] += sent.to_i
        end
      end

      unique_by_channel = unique_users_by_channel

      KNOWN_CHANNELS.map do |channel|
        {
          channel: channel,
          candidate_events: totals[channel][:candidate_events],
          sent_to_make: totals[channel][:sent_to_make],
          unique_users: unique_by_channel.fetch(channel, 0),
          configured: orchestration_event_names.any? { |name| channels_for(name).include?(channel) }
        }
      end
    end

    def unique_users_by_channel
      KNOWN_CHANNELS.index_with do |channel|
        names = orchestration_event_names.select { |name| channels_for(name).include?(channel) }
        next 0 if names.empty?

        scope.where(event_name: names).distinct.count(:user_id)
      end
    end

    # --- Push dispatch results ---------------------------------------------

    def dispatch_scope
      @dispatch_scope ||= PushDispatch.where(created_at: range)
    end

    def dispatch_totals
      @dispatch_totals ||= begin
        row = dispatch_scope.pick(
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE status IN ('#{PROVIDER_ACCEPTED_STATUSES.join("','")}'))"),
          Arel.sql("COUNT(*) FILTER (WHERE status IN ('#{PROVIDER_REJECTED_STATUSES.join("','")}'))"),
          Arel.sql("COUNT(*) FILTER (WHERE status = 'deferred')"),
          Arel.sql("COUNT(*) FILTER (WHERE status = 'skipped')")
        ) || [ 0, 0, 0, 0, 0 ]

        requested, accepted, rejected, deferred, skipped = row.map(&:to_i)
        { requested: requested, accepted: accepted, rejected: rejected, deferred: deferred, skipped: skipped }
      end
    end

    # Correlated through the user_event FK, never through campaign_key:
    # campaign_key names the campaign and copy, which Make versions freely
    # ("first-workout-completed-v1"), so it is a dimension, not a join key.
    def dispatch_counts_by_event
      @dispatch_counts_by_event ||= dispatch_scope
        .joins(:user_event)
        .group("user_events.event_name")
        .pluck(
          Arel.sql("user_events.event_name"),
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE push_dispatches.status IN ('#{PROVIDER_ACCEPTED_STATUSES.join("','")}'))"),
          Arel.sql("COUNT(*) FILTER (WHERE push_dispatches.status IN ('#{PROVIDER_REJECTED_STATUSES.join("','")}'))"),
          Arel.sql("COUNT(*) FILTER (WHERE push_dispatches.status = 'deferred')"),
          Arel.sql("COUNT(*) FILTER (WHERE push_dispatches.status = 'skipped')")
        )
        .each_with_object({}) do |(name, requested, accepted, rejected, deferred, skipped), result|
          result[name] = { requested: requested, accepted: accepted, rejected: rejected, deferred: deferred, skipped: skipped }
        end
    end

    def push_dispatch_results
      totals = dispatch_totals
      skips = dispatch_scope.where(status: "skipped").group(:skip_reason).count
      deferred_reasons = dispatch_scope.where(status: "deferred")
                                       .group(Arel.sql("COALESCE(payload_json ->> 'defer_reason', 'unknown')"))
                                       .count

      {
        requested: totals[:requested],
        provider_accepted: totals[:accepted],
        provider_rejected: totals[:rejected],
        deferred: totals[:deferred],
        skipped: totals[:skipped],
        not_correlated: dispatch_scope.where(user_event_id: nil).count,
        deferred_reasons: deferred_reasons.map { |reason, count| { defer_reason: reason.presence || "unknown", count: count } }
                                          .sort_by { |row| -row[:count] },
        skips: skips.map { |reason, count| { skip_reason: reason.presence || "unknown", count: count } }
                    .sort_by { |row| -row[:count] },
        defer_reasons: PushDispatch::DEFER_REASONS
      }
    end

    # --- Origin -------------------------------------------------------------

    def by_origin
      rows = scope.group(Arel.sql("COALESCE(origin_surface, 'unknown')")).pluck(
        Arel.sql("COALESCE(origin_surface, 'unknown')"),
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(DISTINCT user_id)")
      )

      present = rows.each_with_object({}) { |(surface, events, users), acc| acc[surface] = [ events.to_i, users.to_i ] }

      RelationshipEventTracker::ORIGIN_SURFACES.map do |surface|
        events, users = present.fetch(surface, [ 0, 0 ])
        { origin_surface: surface, events: events, unique_users: users }
      end
    end

    # --- Schedulers ---------------------------------------------------------

    SCHEDULER_KEYS = %w[
      first_workout_not_started_2h first_workout_not_started_24h
      scheduled_workout_reminder relationship_daily_job
      make_pending_retry push_dispatch_deferred
    ].freeze

    def schedulers
      records = ObservabilityHeartbeat.where(key: SCHEDULER_KEYS).index_by(&:key)

      SCHEDULER_KEYS.map do |key|
        record = records[key]
        next { key: key, status: "insufficient_data", registered: false } if record.nil?

        metadata = record.metadata.presence || {}
        {
          key: key,
          registered: true,
          status: record.status,
          expected_interval_seconds: record.expected_interval_seconds,
          last_run_at: record.last_started_at&.iso8601,
          last_success_at: record.last_succeeded_at&.iso8601,
          last_failure_at: record.last_failed_at&.iso8601,
          next_expected_at: record.last_succeeded_at && (record.last_succeeded_at + record.expected_interval_seconds.seconds).iso8601,
          last_error_code: record.last_error_code,
          consecutive_failures: record.consecutive_failures,
          duration_ms: record.last_duration_ms,
          candidates_found: metadata["candidates_found"] || metadata["candidates"],
          events_created: metadata["events_created"] || metadata["event_created"]
        }
      end
    end

    # --- Recent events (drill-down) ----------------------------------------

    # The whole pipeline for one event on one line. This is the view that turns
    # "push is broken" into "the event was created, Make accepted it, and the
    # dispatch was skipped for global_opt_out".
    def recent_events
      scope
        .left_joins(:push_dispatches)
        .order(created_at: :desc)
        .limit(RECENT_EVENTS_LIMIT)
        .pluck(
          Arel.sql("user_events.id"), Arel.sql("user_events.event_name"),
          Arel.sql("user_events.user_id"), Arel.sql("COALESCE(user_events.origin_surface, 'unknown')"),
          Arel.sql("user_events.created_at"), Arel.sql("user_events.make_delivery_status"),
          Arel.sql("user_events.make_last_http_status"), Arel.sql("user_events.make_execution_id"),
          Arel.sql("user_events.make_last_error"),
          Arel.sql("push_dispatches.id"), Arel.sql("push_dispatches.status"),
          Arel.sql("push_dispatches.skip_reason"), Arel.sql("push_dispatches.payload_json ->> 'defer_reason'"),
          Arel.sql("push_dispatches.next_allowed_at"), Arel.sql("push_dispatches.correlation_id")
        )
        .map do |id, name, user_id, origin, created_at, make_status, http_status, execution_id,
                 make_error, dispatch_id, dispatch_status, skip_reason, defer_reason, next_allowed_at, correlation_id|
          {
            event_id: id,
            event_name: name,
            user_id: user_id,
            origin_surface: origin,
            candidate_channels: channels_for(name),
            created_at: created_at&.iso8601,
            make_status: make_status,
            make_http_status: http_status,
            make_execution_id: execution_id,
            make_error: make_error,
            push_dispatch_id: dispatch_id,
            push_status: dispatch_status,
            skip_reason: skip_reason,
            defer_reason: defer_reason,
            next_allowed_at: next_allowed_at&.iso8601,
            correlation_id: correlation_id
          }
        end
    end

    # --- Warnings -----------------------------------------------------------

    def warnings
      list = []
      list.concat(catalog_warnings)
      list.concat(delivery_warnings)
      list.concat(zero_push_warnings)
      list.concat(scheduler_warnings)
      list
    end

    def catalog_warnings
      list = []

      begin
        CommunicationEvents.validate!
      rescue CommunicationEvents::ConfigError => e
        list << warning("orchestration_event_unserializable", "critical",
                        "Catálogo de eventos inválido: #{e.message}")
      end

      drift = MakeWebhookEligibility.allowlist_drift[:env_only]
      if drift.any?
        list << warning("allowlist_drift", "warning",
                        "Evento só no env, sem entrada no YAML: #{drift.join(', ')}. " \
                        "Configure em communication_events.yml ou remova do env.")
      end

      # An event with no decision in either catalog. Critical even at zero
      # volume: the gap is architectural, and it stays invisible precisely while
      # nobody is generating the event yet.
      undecided = uncatalogued_event_names
      if undecided.any?
        volume = uncatalogued_scope.count
        list << warning("uncatalogued_event", "critical",
                        "#{undecided.size} evento(s) do registry sem decisão de orquestração " \
                        "(#{volume} ocorrência(s) no período): #{undecided.join(', ')}. " \
                        "Classifique em communication_events.yml ou non_communication_events.yml.")
      end

      list
    end

    def delivery_warnings
      list = []

      dead = scope.where(make_delivery_status: "dead_letter", make_last_error: "missing_required_context").count
      if dead.positive?
        list << warning("orchestration_event_dead_letter", "critical",
                        "#{dead} evento(s) de orquestração sem contexto obrigatório — falha de contrato, não de rede.")
      end

      # Being "disabled" is only normal when the webhook is globally off or the
      # event had a legitimate reason (no email consent, suppressed producer).
      # Anything else means an orchestration event was born and silently parked.
      if MakeWebhookEligibility.enabled?
        # NULL must count as "no reason given", which is the worst case here.
        # A plain NOT IN would evaluate to NULL and silently drop exactly the
        # rows this warning exists to find.
        unexpected = scope.where(make_delivery_status: "disabled")
                          .where("make_last_error IS NULL OR make_last_error NOT IN (?)",
                                 expected_disabled_reasons)
                          .count
        if unexpected.positive?
          list << warning("orchestration_event_disabled", "warning",
                          "#{unexpected} evento(s) de orquestração com make_delivery_status=disabled sem razão prevista.")
        end
      end

      list
    end

    def expected_disabled_reasons
      %w[no_deliverable_channel suppressed_by_producer user_deleted_or_anonymized
         make_webhook_disabled_or_unconfigured]
    end

    def zero_push_warnings
      list = []
      push_names = orchestration_event_names.select { |name| channels_for(name).include?("push") }
      return list if push_names.empty?

      push_scope = scope.where(event_name: push_names)
      generated = push_scope.count
      accepted = push_scope.where(make_delivery_status: "accepted_by_make").count

      if generated.positive? && accepted.zero?
        list << warning("zero_push_to_make", "critical",
                        "#{generated} evento(s) push gerados e nenhum aceito pelo Make no período.")
      end

      totals = dispatch_totals
      if totals[:requested].positive? && totals[:accepted].zero?
        list << warning("zero_provider_accepted", "critical",
                        "#{totals[:requested]} dispatch(es) solicitados e nenhum aceito pelo provider.")
      end

      list
    end

    def scheduler_warnings
      schedulers.filter_map do |scheduler|
        unless scheduler[:registered]
          next warning("heartbeat_missing", "warning",
                       "Scheduler #{scheduler[:key]} nunca registrou heartbeat. Rode rake observability:heartbeats.")
        end

        next unless %w[warning critical].include?(scheduler[:status])

        warning("scheduler_stale", scheduler[:status] == "critical" ? "critical" : "warning",
                "Scheduler #{scheduler[:key]} está #{scheduler[:status]} " \
                "(último sucesso: #{scheduler[:last_success_at] || 'nunca'}).")
      end
    end

    def warning(code, severity, message)
      { code: code, severity: severity, message: message }
    end
  end
end
