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
  class AndroidInstallations
    PLATFORM = "android".freeze

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
        reconciliation_rate: "linked_at / first_authenticated_request_at"
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
      linked_by_signal = "#{observed} AND linked_at IS NOT NULL"
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
        observed_authenticated: observed,
        link_attempted: "first_link_attempt_at IS NOT NULL",
        linked_by_signal: linked_by_signal,
        observed_unlinked: "#{observed} AND linked_at IS NULL",
        conflicts: bind("last_link_failure_code = ?", "user_conflict"),
        dq_linked_without_authenticated_at: "user_id IS NOT NULL AND last_authenticated_at IS NULL",
        dq_authenticated_at_without_user: "user_id IS NULL AND last_authenticated_at IS NOT NULL",
        dq_linked_without_linked_at: "user_id IS NOT NULL AND linked_at IS NULL",
        dq_linked_without_observed_request: "linked_at IS NOT NULL AND first_authenticated_request_at IS NULL",
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

    def reconciliation
      {
        observed_authenticated_installations: counters[:observed_authenticated],
        link_attempted_installations: counters[:link_attempted],
        linked_installations: counters[:linked_by_signal],
        authenticated_unlinked_installations: counters[:observed_unlinked],
        conflicts: counters[:conflicts],
        failures_by_code: failures_by_code,
        link_rate: link_rate(
          counters[:linked_by_signal],
          counters[:observed_authenticated],
          "android_reconciliation_link_rate_v1"
        )
      }
    end

    def data_quality
      {
        linked_without_last_authenticated_at: counters[:dq_linked_without_authenticated_at],
        authenticated_at_without_user: counters[:dq_authenticated_at_without_user],
        linked_without_linked_at: counters[:dq_linked_without_linked_at],
        linked_without_observed_request: counters[:dq_linked_without_observed_request],
        missing_app_build: counters[:dq_missing_app_build],
        invalid_app_build: counters[:dq_invalid_app_build],
        missing_app_version: counters[:dq_missing_app_version],
        missing_last_seen_at: counters[:dq_missing_last_seen_at]
      }
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
        valid_fcm_tokens: valid_fcm_tokens
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

    def valid_fcm_tokens
      base.where.not(device_token_id: nil)
          .where(device_token_id: DeviceToken.active.select(:id))
          .count
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
    # Days are cut in the reporting timezone, like every other daily metric.
    def health_timeline
      day = ReportingTime.local_date_sql("first_authenticated_request_at")

      base.where(first_authenticated_request_at: TIMELINE_DAYS.days.ago..)
          .group(Arel.sql(day))
          .order(Arel.sql("#{day} DESC"))
          .pluck(
            Arel.sql(day),
            Arel.sql("COUNT(*)"),
            Arel.sql("COUNT(*) FILTER (WHERE linked_at IS NOT NULL)")
          )
          .map do |date, total, linked|
            {
              date: date.to_s,
              observed_authenticated_installations: total,
              linked_installations: linked,
              link_rate: link_rate(linked, total, "android_daily_reconciliation_rate_v1")
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
      linked = counters[:linked_by_signal]
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

    # Keyed on USERS (not installations) end to end, so counts and denominator
    # always describe the same population.
    def user_funnel
      linked_users = User.where(id: base.linked.select(:user_id))
      total = unique_linked_users
      created = linked_users.where(id: WorkoutPlan.select(:user_id)).count
      completed = linked_users
                  .where(id: WorkoutSession.where(completion_status: "completed").select(:user_id))
                  .count

      [
        funnel_step("Usuários Android vinculados", total, total),
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
