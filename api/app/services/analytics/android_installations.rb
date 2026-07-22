module Analytics
  # "APP ANDROID" panel (Fase 23) — the real installed base, sourced from
  # app_installations (NOT the write-once users.activation_platform behind the
  # old n=1). Separates the four things that must never be conflated:
  # Installations / Devices / Users / Sessions.
  #
  # Honest by construction:
  #   - "registered_live" = installs seen by the new tracker (source register).
  #   - "backfilled"      = historical installs inferred from device_tokens.
  #   - tracking_coverage = registered_live / known, so the panel shows how much
  #     of the base the live tracker already observes (grows as the app updates).
  class AndroidInstallations
    PLATFORM = "android".freeze

    def call
      {
        installations: installation_cards,
        users: user_cards,
        activity: activity_cards,
        push: push_cards,
        sessions: session_cards,
        versions: version_rows,
        tracking_coverage: tracking_coverage,
        funnel: funnel,
        source: "app_installations",
        generated_at: ReportingTime.now.iso8601
      }
    end

    private

    def base
      AppInstallation.for_platform(PLATFORM)
    end

    def installation_cards
      {
        known: base.count,
        authenticated: base.authenticated.count,
        anonymous: base.anonymous.count,
        registered_live: base.where(source: "register").count,
        backfilled: base.where(source: "backfill_device_token").count
      }
    end

    def user_cards
      { identified: base.where.not(user_id: nil).distinct.count(:user_id) }
    end

    def activity_cards
      {
        active_today: base.active_since(ReportingTime.today.beginning_of_day).count,
        active_7d: base.active_since(7.days.ago).count,
        active_30d: base.active_since(30.days.ago).count,
        new_30d: base.where(first_seen_at: 30.days.ago..).count
      }
    end

    def push_cards
      {
        permission_granted: base.where(notification_permission: "granted").count,
        push_enabled: base.where(push_enabled: true).count,
        valid_fcm_tokens: base.where.not(device_token_id: nil)
                              .where(device_token_id: DeviceToken.active.select(:id)).count
      }
    end

    def session_cards
      with_session = base.where.not(last_session_at: nil)
      {
        with_session: with_session.count,
        events_received: ProductAnalyticsEvent.where(platform: PLATFORM).count
      }
    end

    # Top app versions by installed count with basic activity breakdown.
    def version_rows
      base.group(:app_version).count.sort_by { |_v, n| -n }.first(20).map do |version, installs|
        scope = base.where(app_version: version)
        {
          app_version: version.presence || "(desconhecida)",
          installations: installs,
          active_7d: scope.active_since(7.days.ago).count,
          push_enabled: scope.where(push_enabled: true).count
        }
      end
    end

    # Coverage = installs the live tracker has registered / all known installs.
    def tracking_coverage
      known = base.count
      registered = base.where(source: "register").count
      MetricResult.ratio(
        numerator: registered, denominator: known,
        definition: "android_tracking_coverage_v1"
      )
    end

    # Installation → authenticated → workout created → workout completed.
    # User-keyed steps use the users linked to Android installs (real base),
    # never behavioural inference.
    def funnel
      known = base.count
      user_ids = base.where.not(user_id: nil).distinct.pluck(:user_id)
      authenticated = user_ids.size
      created = User.where(id: user_ids).where(id: WorkoutPlan.select(:user_id)).count
      completed = User.where(id: user_ids)
                     .where(id: WorkoutSession.where(completion_status: "completed").select(:user_id))
                     .count

      [
        step("Instalação conhecida", known, known),
        step("Instalação autenticada", authenticated, known),
        step("Treino criado", created, known),
        step("Treino concluído", completed, known)
      ]
    end

    def step(label, count, base_count)
      {
        label: label,
        count: count,
        conversion: MetricResult.ratio(
          numerator: count, denominator: base_count,
          definition: "android_funnel_step_v1"
        )
      }
    end
  end
end
