module Analytics
  # "NOVOS USUÁRIOS" block of the admin Usuários section: how many accounts were
  # created inside a window, and where each one was created FROM.
  #
  # The one question this exists to answer is "of the users created since Monday,
  # how many actually came from Android?" — which the panel could not answer
  # because it mixed all-time history, web and Android, and because until
  # users.signup_source existed no column recorded the origin of a signup at all.
  #
  # signup_source is the ONLY field read for origin here. Deliberately NOT used:
  #   * activation_platform — the platform of the FIRST product analytics event.
  #     Later than the signup and null on most accounts.
  #   * consent_source — hardcoded "web" in two of the three creation sites.
  #   * the existence of an AppInstallation — that proves "this user used
  #     Android", never "this user created the account from Android". A user whose
  #     installation shows up months after signup must NOT be reclassified.
  #
  # Read-only by construction: every method here is a SELECT. Nothing in this
  # service writes a record or emits an event.
  class SignupCohort
    ANDROID = "android".freeze
    UNKNOWN = "unknown".freeze

    PERIODS = %w[since_monday today 7d 30d all].freeze
    DEFAULT_PERIOD = "since_monday".freeze

    # Auth-attempt events that are actually emitted today. login_started,
    # login_completed and social_login_* are in the taxonomy but no code path
    # emits them, so including them would add guaranteed zeros that read as
    # "nobody tried" rather than "not instrumented".
    ATTEMPT_EVENTS = %w[
      android_registration_started
      android_registration_failed
      google_auth_started
      google_auth_failed
    ].freeze

    UNKNOWN_NOTE = "\"Desconhecido\" NÃO significa web: significa que a origem não foi observada. " \
                   "Inclui todas as contas criadas antes desta instrumentação.".freeze

    def initialize(period: nil, source: nil)
      @period = PERIODS.include?(period.to_s) ? period.to_s : DEFAULT_PERIOD
      @source = EventCatalog::PLATFORMS.include?(source.to_s) ? source.to_s : nil
    end

    attr_reader :period, :source

    # The window, in the REPORTING zone (America/Sao_Paulo) — never in Time.zone,
    # which is UTC in this app (config.time_zone is commented out in
    # config/application.rb). A signup at 23:30 on Sunday in São Paulo is 02:30Z
    # on Monday; cutting the week in UTC would place it inside "desde segunda",
    # which is false for the person who actually used the app.
    #
    # TimeWithZone#beginning_of_week keeps the zone and zeroes the clock IN it, so
    # this really is midnight Monday in São Paulo (== 03:00Z).
    #
    # Progress::WeekRange is not reusable here: it is Sunday-to-Saturday and reads
    # Time.zone (UTC).
    #
    # Binding a TimeWithZone against a UTC column is exact and needs no
    # AT TIME ZONE: created_at is a timestamp holding the instant in UTC, and the
    # adapter converts the bind value with getutc before quoting. So
    # `where(created_at: window)` emits UTC boundaries already shifted from the
    # local ones. ReportingTime.local_date_sql is only needed when GROUPING by
    # local day (as health_timeline does); here it would also defeat the index.
    def window
      return @window if defined?(@window)

      now = ReportingTime.now
      @window =
        case @period
        when "all" then nil
        when "today" then now.beginning_of_day..now
        when "7d" then (now.beginning_of_day - 6.days)..now
        when "30d" then (now.beginning_of_day - 29.days)..now
        else now.beginning_of_week(:monday)..now
        end
    end

    def call
      { summary: summary, android_funnel: android_funnel, definitions: definitions }
    end

    # Accounts created inside the window, broken down by observed origin.
    #
    # Counted over User.all, matching the listing right below it in the panel. The
    # analytics denominator (User.reportable, which drops test/internal/anonymized
    # accounts) is reported ALONGSIDE, never instead: if the cards counted
    # reportable while the table listed all, the two would silently disagree and
    # the admin would be unable to reconcile them by counting rows.
    def summary
      counts = signup_source_counts
      total = counts.values.sum

      {
        total: total,
        by_source: counts,
        reportable_total: cohort_scope(User.reportable).count,
        unknown_share: MetricResult.ratio(
          numerator: counts[UNKNOWN],
          denominator: total,
          definition: "signup_source_unknown_share_v1",
          note: UNKNOWN_NOTE
        )
      }
    end

    # Android diagnostic funnel over the SAME window.
    #
    # These are NOT stages of one conversion funnel: installations and users are
    # different populations. Every ratio therefore names its own denominator, and
    # nothing is divided across populations — that is how a fake "50%" is born.
    def android_funnel
      counts = installation_counters
      observed = counts[:observed]

      {
        installations_observed: observed,
        reached_authentication: MetricResult.ratio(
          numerator: counts[:reached_auth],
          denominator: observed,
          definition: "android_window_reached_authentication_v1"
        ),
        users_created_from_android: android_users_created,
        linked_installations: MetricResult.ratio(
          numerator: counts[:linked],
          denominator: observed,
          definition: "android_window_linked_installations_v1"
        ),
        anonymous_installations: counts[:anonymous],
        auth_attempt_events: auth_attempt_events
      }
    end

    def definitions
      {
        period: @period,
        source: @source,
        timezone: ReportingTime.zone.tzinfo.name,
        window_from: window&.first&.iso8601,
        window_to: window&.last&.iso8601,
        generated_at: ReportingTime.now.iso8601,
        signup_source: "Plataforma observada no momento da criação da conta (header X-Platform, " \
                       "ou omniauth.params no fluxo Google web). Nunca inferida a partir de " \
                       "instalações, eventos ou consentimento.",
        unknown_note: UNKNOWN_NOTE,
        installations_observed: "Instalações Android criadas OU vistas dentro da janela " \
                                "(first_seen_at ou last_seen_at na janela). É base ativa na " \
                                "janela, não aquisição de novas instalações.",
        reached_authentication: "Instalações com requisição autenticada observada dentro da " \
                               "janela. Esse marco só é gravado APÓS um login bem-sucedido, " \
                               "portanto zero aqui não significa \"ninguém tentou\".",
        users_created_from_android: "Contas com created_at na janela E signup_source=android. " \
                                    "São usuários, não instalações — não dividir pelas linhas acima.",
        linked_installations: "Instalações observadas que já possuem usuário vinculado.",
        anonymous_installations: "Instalações observadas que seguem sem usuário vinculado.",
        auth_attempt_events: "Contagem de EVENTOS de tentativa de autenticação Android, não de " \
                             "pessoas: um mesmo aparelho que tenta 5 vezes conta 5. Existe para " \
                             "separar \"ninguém tentou\" de \"tentaram e falhou\"."
      }
    end

    private

    def cohort_scope(scope)
      scope = scope.where(created_at: window) if window
      scope = scope.where(signup_source: @source) if @source
      scope
    end

    # One COUNT(*) FILTER pass instead of four queries. index_with guarantees all
    # four platforms are present: a source with zero signups must render as 0, not
    # vanish from the payload — a missing card reads as "not instrumented".
    #
    # Note this ignores @source on purpose: the breakdown is what makes the
    # origin filter meaningful, so it always shows the whole cohort.
    def signup_source_counts
      scope = User.all
      scope = scope.where(created_at: window) if window

      select = EventCatalog::PLATFORMS.map do |platform|
        "COUNT(*) FILTER (WHERE #{bind('signup_source = ?', platform)}) AS c_#{platform}"
      end.join(", ")

      row = Array(scope.pick(Arel.sql(select)))
      EventCatalog::PLATFORMS.zip(row).to_h.transform_values(&:to_i)
    end

    def android_users_created
      scope = User.where(signup_source: ANDROID)
      scope = scope.where(created_at: window) if window
      scope.count
    end

    def installation_counters
      @installation_counters ||= begin
        conditions = {
          observed: observed_sql,
          reached_auth: "#{observed_sql} AND (#{reached_auth_sql})",
          linked: "#{observed_sql} AND user_id IS NOT NULL",
          anonymous: "#{observed_sql} AND user_id IS NULL"
        }
        select = conditions.map { |key, cond| "COUNT(*) FILTER (WHERE #{cond}) AS c_#{key}" }.join(", ")
        row = Array(AppInstallation.for_platform(ANDROID).pick(Arel.sql(select)))
        conditions.keys.zip(row).to_h.transform_values(&:to_i)
      end
    end

    # "criada/vista dentro da janela": either endpoint of the installation's
    # lifetime falling inside the window is enough.
    def observed_sql
      @observed_sql ||=
        if window
          "(#{bind('first_seen_at BETWEEN ? AND ?', window.first, window.last)} OR " \
          "#{bind('last_seen_at BETWEEN ? AND ?', window.first, window.last)})"
        else
          "TRUE"
        end
    end

    def reached_auth_sql
      @reached_auth_sql ||=
        if window
          bind("first_authenticated_request_at BETWEEN ? AND ?", window.first, window.last)
        else
          "first_authenticated_request_at IS NOT NULL"
        end
    end

    # EVENTS, not people. platform comes from the X-Platform header via
    # Observability::Context, so an auth attempt made through the Google WEB
    # redirect from inside the Android app is invisible here: that callback is a
    # browser navigation from Google and carries no header, landing as "unknown".
    # A zero is therefore "no Android-attributed attempt", not "no attempt".
    def auth_attempt_events
      scope = ProductAnalyticsEvent.for_platform(ANDROID).where(event_name: ATTEMPT_EVENTS)
      scope = scope.in_window(window) if window
      scope.group(:event_name).count.reverse_merge(ATTEMPT_EVENTS.index_with(0))
    end

    def bind(condition, *values)
      ApplicationRecord.sanitize_sql_array([ condition, *values ])
    end
  end
end
