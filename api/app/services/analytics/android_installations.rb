module Analytics
  # "APP ANDROID" panel — the real installed base, sourced from app_installations
  # and nothing else. AppInstallation is the ONLY source of truth for how many
  # installations exist; activation_platform, device_tokens, product analytics
  # events and sessions are complementary signals that live in their own blocks
  # and must never be read as an installation count.
  #
  # Operational reconciliation is measured from observed authenticated requests,
  # never from app_build. The Android shell loads the remote web bundle, so the
  # native build is useful release metadata but not eligibility for linking.
  #
  # This panel never reports Google Play downloads: an installation record is
  # created when the app first talks to the API, which is a different (smaller)
  # number than the store's official install count.
  #
  # THE LINK IS user_id. linked_at only records links created by the current
  # LinkToUser flow, so an installation linked before that column existed has a
  # user_id and no linked_at. Reading linked_at as proof of the current link
  # would report those legacy rows as unlinked — they are not. linked_at stays
  # for "how is the new mechanism performing", never for "is this linked".
  class AndroidInstallations
    PLATFORM = "android".freeze

    # Wording avoids the raw column name on purpose: the payload is asserted to
    # carry no "user_id" substring, so a leak of the real column is detectable.
    LINKED_AT_NOTE = "A coluna linked_at registra apenas vínculos realizados pelo fluxo novo. " \
                     "Instalações vinculadas antes da instrumentação aparecem como vinculadas, " \
                     "mesmo sem linked_at — isso é esperado, não é falha.".freeze

    RECONCILIATION_RATE_DEFINITION =
      "instalações com usuário vinculado ÷ instalações com requisição autenticada observada".freeze

    VERSIONS_LIMIT = 20
    MANUFACTURERS_LIMIT = 10
    DEVICE_MODELS_LIMIT = 15
    OS_VERSIONS_LIMIT = 15
    TIMELINE_DAYS = 14

    # Link-rate thresholds shared with the admin UI (presentation constants).
    HEALTHY_LINK_RATE = 95.0
    ATTENTION_LINK_RATE = 85.0

    # Google Play integration does not exist yet. The block is exposed with
    # configured:false so the panel can show the slot without ever inventing a
    # number — the official install count only comes from the Play Console.
    GOOGLE_PLAY_PLACEHOLDER = {
      configured: false,
      official_installs: nil,
      last_synced_at: nil,
      source: nil
    }.freeze

    def call
      {
        source: "app_installations",
        generated_at: ReportingTime.now.iso8601,
        definitions: definitions,
        overview: overview,
        reconciliation: reconciliation,
        data_quality: data_quality,
        adoption: adoption,
        health_timeline: health_timeline,
        operational_health: operational_health,
        installation_provenance: installation_provenance,
        push: push,
        analytics_pipeline: analytics_pipeline,
        google_play: GOOGLE_PLAY_PLACEHOLDER,
        versions: versions,
        manufacturers: manufacturers,
        device_models: device_models,
        operating_system_versions: operating_system_versions,
        acquisition_split: acquisition_split,
        user_funnel: user_funnel
      }
    end

    private

    def base
      AppInstallation.for_platform(PLATFORM)
    end

    # Parenthesised so it can be embedded in any comparison safely.
    def numeric_build
      "(#{AppInstallation::NUMERIC_BUILD_SQL})"
    end

    def active_7d_since
      @active_7d_since ||= 7.days.ago
    end

    def active_30d_since
      @active_30d_since ||= 30.days.ago
    end

    def definitions
      {
        active_7d_since: active_7d_since.iso8601,
        active_30d_since: active_30d_since.iso8601,
        timeline_days: TIMELINE_DAYS,
        healthy_link_rate: HEALTHY_LINK_RATE,
        attention_link_rate: ATTENTION_LINK_RATE,
        reconciliation_rate: RECONCILIATION_RATE_DEFINITION,
        linked_at_note: LINKED_AT_NOTE
      }
    end

    # ---------------------------------------------------------------- counters

    # Every headline count in one pass over the android partition, using
    # conditional aggregation. Replaces the ~20 separate COUNT queries the panel
    # used to run. Timestamps are bound, never string-interpolated.
    def counters
      @counters ||= begin
        conditions = counter_conditions
        # Aliases are prefixed so they can never collide with a real column name:
        # an alias like "push_enabled" would make Rails cast the count with the
        # boolean column type and return true/false instead of a number.
        select = conditions.map { |key, cond| "COUNT(*) FILTER (WHERE #{cond}) AS c_#{key}" }.join(", ")
        row = Array(base.pick(Arel.sql(select)))
        conditions.keys.zip(row).to_h.transform_values(&:to_i)
      end
    end

    def counter_conditions
      linked = "user_id IS NOT NULL"
      anon = "user_id IS NULL"
      auth = "user_id IS NOT NULL AND last_authenticated_at IS NOT NULL"
      observed = "first_authenticated_request_at IS NOT NULL"
      missing_build = "app_build IS NULL OR btrim(app_build) = ''"

      {
        total: "TRUE",
        linked: linked,
        anonymous: anon,
        authenticated: auth,
        active_7d: bind("last_seen_at >= ?", active_7d_since),
        active_30d: bind("last_seen_at >= ?", active_30d_since),
        active_24h: bind("last_seen_at >= ?", 24.hours.ago),
        new_24h: bind("first_seen_at >= ?", 24.hours.ago),
        new_7d: bind("first_seen_at >= ?", active_7d_since),
        new_30d: bind("first_seen_at >= ?", active_30d_since),
        # Denominator: the installation was seen in an authenticated request.
        observed_authenticated: observed,
        link_attempted: "first_link_attempt_at IS NOT NULL",
        # Numerator: user_id is the link. NOT linked_at.
        authenticated_linked: "#{observed} AND #{linked}",
        authenticated_unlinked: "#{observed} AND #{anon}",
        # linked_at only measures the current LinkToUser flow.
        new_flow_linked: "linked_at IS NOT NULL",
        legacy_linked_observed: "#{observed} AND #{linked} AND linked_at IS NULL",
        conflicts: bind("last_link_failure_code = ?", "user_conflict"),
        dq_linked_without_authenticated_at: "user_id IS NOT NULL AND last_authenticated_at IS NULL",
        dq_authenticated_at_without_user: "user_id IS NULL AND last_authenticated_at IS NOT NULL",
        # A link timestamp with no owner is a real contradiction.
        dq_linked_at_without_user: "linked_at IS NOT NULL AND #{anon}",
        dq_authenticated_request_without_user: "#{observed} AND #{anon}",
        dq_linked_at_without_observed_request: "linked_at IS NOT NULL AND first_authenticated_request_at IS NULL",
        dq_missing_app_build: missing_build,
        dq_invalid_app_build: "NOT (#{missing_build}) AND #{numeric_build} IS NULL",
        dq_missing_app_version: "app_version IS NULL OR btrim(app_version) = ''",
        dq_missing_last_seen_at: "last_seen_at IS NULL",
        registered_live: bind("source = ?", "register"),
        backfilled: bind("source = ?", "backfill_device_token"),
        permission_granted: bind("notification_permission = ?", "granted"),
        push_enabled: "push_enabled",
        with_session: "last_session_at IS NOT NULL"
      }
    end

    def bind(condition, value)
      ApplicationRecord.sanitize_sql_array([ condition, value ])
    end

    # ---------------------------------------------------------------- sections

    def overview
      {
        total_installations: counters[:total],
        linked_installations: counters[:linked],
        anonymous_installations: counters[:anonymous],
        authenticated_installations: counters[:authenticated],
        unique_linked_users: unique_linked_users,
        users_with_multiple_installations: users_with_multiple_installations,
        active_installations_7d: counters[:active_7d],
        active_installations_30d: counters[:active_30d],
        new_installations_24h: counters[:new_24h],
        new_installations_7d: counters[:new_7d],
        new_installations_30d: counters[:new_30d],
        link_rate: link_rate(counters[:linked], counters[:total], "android_link_rate_v1")
      }
    end

    # The operational rate is user_id over observed authenticated requests. The
    # linked_at figures ride alongside as new-flow instrumentation, never as the
    # definition of "linked".
    def reconciliation
      {
        observed_authenticated_installations: counters[:observed_authenticated],
        link_attempted_installations: counters[:link_attempted],
        linked_installations: counters[:authenticated_linked],
        authenticated_unlinked_installations: counters[:authenticated_unlinked],
        new_flow_linked_installations: counters[:new_flow_linked],
        legacy_linked_observed_installations: counters[:legacy_linked_observed],
        new_flow_link_latency_seconds: new_flow_link_latency_seconds,
        conflicts: counters[:conflicts],
        failures_by_code: failures_by_code,
        link_rate: link_rate(
          counters[:authenticated_linked],
          counters[:observed_authenticated],
          "android_operational_link_rate_v1"
        )
      }
    end

    # Real contradictions only. A legacy link (user_id present, linked_at null)
    # is an expected post-migration state and is reported in `reconciliation`,
    # never here — counting it as a defect is what produced the false 50%.
    def data_quality
      {
        linked_without_last_authenticated_at: counters[:dq_linked_without_authenticated_at],
        authenticated_at_without_user: counters[:dq_authenticated_at_without_user],
        linked_at_without_user: counters[:dq_linked_at_without_user],
        authenticated_request_without_user: counters[:dq_authenticated_request_without_user],
        linked_at_without_observed_request: counters[:dq_linked_at_without_observed_request],
        missing_app_build: counters[:dq_missing_app_build],
        invalid_app_build: counters[:dq_invalid_app_build],
        missing_app_version: counters[:dq_missing_app_version],
        missing_last_seen_at: counters[:dq_missing_last_seen_at]
      }
    end

    # Efficiency of the new flow, in seconds between the observed authenticated
    # request and the link it produced. Only rows that actually have linked_at
    # take part — a legacy row has no measurable duration and must not be
    # imputed one.
    def new_flow_link_latency_seconds
      median = base.where.not(linked_at: nil)
                   .where.not(first_authenticated_request_at: nil)
                   .pick(Arel.sql(
                     "PERCENTILE_CONT(0.5) WITHIN GROUP (" \
                     "ORDER BY EXTRACT(EPOCH FROM (linked_at - first_authenticated_request_at)))"
                   ))

      median&.to_f&.round(1)
    end

    # Where the record came from — NOT a measure of tracking health. Kept apart
    # from link_rate on purpose: a backfilled install is a real install.
    def installation_provenance
      {
        registered_live: counters[:registered_live],
        backfilled: counters[:backfilled],
        coverage: link_rate(
          counters[:registered_live], counters[:total],
          "android_installation_provenance_v1"
        )
      }
    end

    def push
      {
        permission_granted: counters[:permission_granted],
        push_enabled: counters[:push_enabled],
        installations_with_active_token: installations_with_active_token
      }
    end

    # Event pipeline health. These are events and sessions, never installations.
    def analytics_pipeline
      events = ProductAnalyticsEvent.for_platform(PLATFORM)
      {
        android_events_total: events.count,
        android_events_7d: events.where(occurred_at: active_7d_since..).count,
        installations_with_session: counters[:with_session],
        last_event_at: events.maximum(:occurred_at)&.iso8601
      }
    end

    def unique_linked_users
      @unique_linked_users ||= base.linked.distinct.count(:user_id)
    end

    def users_with_multiple_installations
      base.linked.group(:user_id).having(Arel.sql("COUNT(*) > 1")).count.size
    end

    # Installations joined to an ACTIVE DeviceToken row.
    #
    # This measures the installation↔token linkage, NOT how many devices can
    # receive a push. Nothing in the live code writes app_installations.
    # device_token_id: DeviceTokensController registers the token without ever
    # touching the installation, so the column is only ever populated by the
    # historical backfill. Where it is empty the linkage is simply not
    # instrumented, and answering 0 would read as "no device can receive push"
    # — a push outage — instead of "this join does not exist yet".
    #
    # nil therefore means NOT INSTRUMENTED and must be rendered as such. Real
    # push reach lives in the device_tokens component, which counts DeviceToken
    # directly and does not depend on this join.
    def installations_with_active_token
      linked_to_any_token = base.where.not(device_token_id: nil)
      return nil unless linked_to_any_token.exists?

      linked_to_any_token.where(device_token_id: DeviceToken.active.select(:id)).count
    end

    def link_rate(numerator, denominator, definition)
      MetricResult.ratio(numerator: numerator, denominator: denominator, definition: definition)
    end

    def failures_by_code
      @failures_by_code ||= base.where.not(last_link_failure_code: [ nil, "" ])
                                .group(:last_link_failure_code)
                                .order(Arel.sql("COUNT(*) DESC"))
                                .count
    end

    # ------------------------------------------------------------- aggregations

    # One grouped query per breakdown — no per-row follow-up queries.
    def versions
      linked_count = "COUNT(*) FILTER (WHERE user_id IS NOT NULL)"
      base.group(:app_version, :app_build)
          .order(Arel.sql("MAX(#{numeric_build}) DESC NULLS LAST, COUNT(*) DESC"))
          .limit(VERSIONS_LIMIT)
          .pluck(
            :app_version,
            :app_build,
            Arel.sql("MAX(#{numeric_build})"),
            Arel.sql("COUNT(*)"),
            Arel.sql(linked_count),
            Arel.sql("COUNT(*) FILTER (WHERE user_id IS NULL)"),
            Arel.sql("COUNT(*) FILTER (WHERE #{bind('last_seen_at >= ?', active_7d_since)})")
          )
          .map do |version, build, numeric, total, linked, anonymous, active_7d|
            {
              app_version: version.presence,
              app_build: build.presence,
              build_number: numeric,
              total_installations: total,
              linked_installations: linked,
              anonymous_installations: anonymous,
              active_installations_7d: active_7d,
              link_rate: link_rate(linked, total, "android_link_rate_v1")
            }
          end
    end

    def manufacturers
      base.group(:device_manufacturer)
          .order(Arel.sql("COUNT(*) DESC"))
          .limit(MANUFACTURERS_LIMIT)
          .pluck(
            :device_manufacturer,
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(*) FILTER (WHERE user_id IS NOT NULL)"),
            Arel.sql("COUNT(*) FILTER (WHERE #{bind('last_seen_at >= ?', active_30d_since)})")
          )
          .map do |manufacturer, total, linked, active_30d|
            {
              manufacturer: manufacturer.presence,
              total_installations: total,
              linked_installations: linked,
              active_installations_30d: active_30d
            }
          end
    end

    def device_models
      base.group(:device_manufacturer, :device_model)
          .order(Arel.sql("COUNT(*) DESC"))
          .limit(DEVICE_MODELS_LIMIT)
          .pluck(
            :device_manufacturer,
            :device_model,
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(*) FILTER (WHERE #{bind('last_seen_at >= ?', active_30d_since)})")
          )
          .map do |manufacturer, model, total, active_30d|
            {
              manufacturer: manufacturer.presence,
              device_model: model.presence,
              total_installations: total,
              active_installations_30d: active_30d
            }
          end
    end

    def operating_system_versions
      base.group(:operating_system_version)
          .order(Arel.sql("COUNT(*) DESC"))
          .limit(OS_VERSIONS_LIMIT)
          .pluck(:operating_system_version, Arel.sql("COUNT(*)"))
          .map do |os_version, total|
            { operating_system_version: os_version.presence, total_installations: total }
          end
    end

    # ---------------------------------------------------------------- adoption

    # Which version/build the base actually runs, and how fast the newest build
    # is being picked up after a release.
    def adoption
      latest = build_counts.max_by(&:first)
      most_used_build = build_counts.max_by(&:last)
      latest_installs = latest ? latest.last : 0

      {
        most_used_version: most_used_version&.first,
        most_used_version_installations: most_used_version&.last || 0,
        most_used_build: most_used_build&.first,
        most_used_build_installations: most_used_build&.last || 0,
        latest_build: latest&.first,
        latest_build_installations: latest_installs,
        latest_build_share: link_rate(latest_installs, counters[:total], "android_latest_build_share_v1")
      }
    end

    def build_counts
      @build_counts ||= base.where(Arel.sql("#{numeric_build} IS NOT NULL"))
                            .group(Arel.sql(numeric_build))
                            .pluck(Arel.sql(numeric_build), Arel.sql("COUNT(*)"))
    end

    def most_used_version
      @most_used_version ||= base.where.not(app_version: [ nil, "" ])
                                 .group(:app_version)
                                 .order(Arel.sql("COUNT(*) DESC"))
                                 .limit(1)
                                 .pluck(:app_version, Arel.sql("COUNT(*)"))
                                 .first
    end

    # ---------------------------------------------------------------- timeline

    # Daily reconciliation rate for installs observed in authenticated requests.
    # Linked means user_id; the linked_at column is reported beside it so the new
    # flow's share of those links stays visible without defining the rate.
    # Days are cut in the reporting timezone, like every other daily metric.
    def health_timeline
      day = ReportingTime.local_date_sql("first_authenticated_request_at")

      base.where(first_authenticated_request_at: TIMELINE_DAYS.days.ago..)
          .group(Arel.sql(day))
          .order(Arel.sql("#{day} DESC"))
          .pluck(
            Arel.sql(day),
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(*) FILTER (WHERE user_id IS NOT NULL)"),
            Arel.sql("COUNT(*) FILTER (WHERE linked_at IS NOT NULL)")
          )
          .map do |date, total, linked, new_flow_linked|
            {
              date: date.to_s,
              observed_authenticated_installations: total,
              linked_installations: linked,
              new_flow_linked_installations: new_flow_linked,
              link_rate: link_rate(linked, total, "android_daily_operational_link_rate_v1")
            }
          end
    end

    # ------------------------------------------------------- operational health

    # Status of each moving part of the Android stack, derived ONLY from real
    # signals. When there is no signal the component reports "unknown" — it is
    # never optimistically reported as healthy.
    def operational_health
      [
        tracking_component,
        reconciliation_component,
        push_component,
        analytics_component,
        webhooks_component,
        device_tokens_component
      ]
    end

    def component(key, label, status, detail)
      { key: key, label: label, status: status, detail: detail }
    end

    def tracking_component
      unless ::AppInstallations::Register.enabled?
        return component(:tracking, "Tracking Android", "critical",
                         "registro de instalações desligado (MOBILE_ANALYTICS_ENABLED)")
      end

      if counters[:total].zero?
        component(:tracking, "Tracking Android", "unknown", "nenhuma instalação Android registrada")
      elsif counters[:active_24h].positive?
        component(:tracking, "Tracking Android", "ok",
                  "#{counters[:active_24h]} instalação(ões) vista(s) nas últimas 24h")
      else
        component(:tracking, "Tracking Android", "attention",
                  "nenhuma instalação vista nas últimas 24h")
      end
    end

    def reconciliation_component
      total = counters[:observed_authenticated]
      linked = counters[:authenticated_linked]
      label = "Reconciliação"

      if total.zero?
        return component(:reconciliation, label, "unknown",
                         "nenhuma instalação observada em requisição autenticada")
      end

      rate = (linked.to_f / total * 100).round(1)
      status =
        if rate >= HEALTHY_LINK_RATE
          "ok"
        elsif rate >= ATTENTION_LINK_RATE
          "attention"
        else
          "critical"
        end

      component(:reconciliation, label, status,
                "#{linked} de #{total} instalações observadas autenticadas vinculadas")
    end

    def push_component
      label = "Push"
      return component(:push, label, "critical", "Firebase não configurado") unless FirebasePushService.configured?

      active = DeviceToken.active.where(platform: PLATFORM).count
      if active.positive?
        component(:push, label, "ok", "#{active} token(s) Android ativo(s)")
      else
        component(:push, label, "unknown", "nenhum token Android ativo")
      end
    end

    def analytics_component
      label = "Analytics"
      unless Ingestion.enabled?
        return component(:analytics, label, "critical", "ingestão desligada (ANALYTICS_INGESTION_ENABLED)")
      end

      recent = ProductAnalyticsEvent.for_platform(PLATFORM).where(occurred_at: 24.hours.ago..).count
      if recent.positive?
        component(:analytics, label, "ok", "#{recent} evento(s) Android nas últimas 24h")
      else
        component(:analytics, label, "unknown", "nenhum evento Android nas últimas 24h")
      end
    end

    # Outbound Make delivery — the shared webhook path for lifecycle events.
    def webhooks_component
      label = "Webhooks (Make)"
      recent = UserEvent.where(created_at: 24.hours.ago..).group(:make_delivery_status).count
      delivered = recent["accepted_by_make"].to_i + recent["delivered"].to_i
      failed = recent["failed_to_reach_make"].to_i + recent["dead_letter"].to_i + recent["failed"].to_i

      if delivered.zero? && failed.zero?
        component(:webhooks, label, "unknown", "nenhuma entrega nas últimas 24h")
      elsif failed.zero?
        component(:webhooks, label, "ok", "#{delivered} entrega(s) sem falhas em 24h")
      elsif failed > delivered
        component(:webhooks, label, "critical", "#{failed} falha(s) para #{delivered} entrega(s) em 24h")
      else
        component(:webhooks, label, "attention", "#{failed} falha(s) para #{delivered} entrega(s) em 24h")
      end
    end

    def device_tokens_component
      label = "Device Tokens"
      scope = DeviceToken.where(platform: PLATFORM)
      active = scope.active.count
      invalidated = scope.where.not(invalidated_at: nil).count

      if active.zero? && invalidated.zero?
        component(:device_tokens, label, "unknown", "nenhum token Android registrado")
      elsif active.zero?
        component(:device_tokens, label, "critical",
                  "nenhum token ativo (#{invalidated} invalidado(s))")
      elsif invalidated > active
        component(:device_tokens, label, "attention",
                  "#{active} ativo(s) contra #{invalidated} invalidado(s)")
      else
        component(:device_tokens, label, "ok", "#{active} ativo(s), #{invalidated} invalidado(s)")
      end
    end

    # ------------------------------------------------------------- user funnel

    # Every account linked to an Android install, split by who it actually is.
    # Reported beside the funnel (never merged into it) so "Todos" stays
    # inspectable: the point is to see the robots, not to pretend they never ran.
    def acquisition_split
      linked_users = User.where(id: base.linked.select(:user_id))

      {
        total: linked_users.count,
        external: AccountClassification.exclude_non_external(linked_users).count,
        internal: AccountClassification.internal_scope(linked_users).count,
        automated_test: AccountClassification.automated_test_scope(linked_users).count
      }
    end

    # Keyed on USERS (not installations) end to end, so counts and denominator
    # always describe the same population.
    #
    # EXTERNAL users only. Google Play's pre-launch report drives a real device
    # through the entire sign-up on a @cloudtestlabaccounts.com account, so
    # counting it here is what made a release with zero real acquisition read as
    # "2 linked users, 100% converted". The unfiltered totals are in
    # acquisition_split above.
    def user_funnel
      linked_users = AccountClassification.exclude_non_external(
        User.where(id: base.linked.select(:user_id))
      )
      total = linked_users.count
      created = linked_users.where(id: WorkoutPlan.select(:user_id)).count
      completed = linked_users
                  .where(id: WorkoutSession.where(completion_status: "completed").select(:user_id))
                  .count

      [
        funnel_step("Usuários Android vinculados (externos)", total, total),
        funnel_step("Criou treino", created, total),
        funnel_step("Concluiu treino", completed, total)
      ]
    end

    def funnel_step(label, count, denominator)
      {
        label: label,
        count: count,
        conversion: link_rate(count, denominator, "android_user_funnel_step_v1")
      }
    end
  end
end
