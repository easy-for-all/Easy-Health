module Analytics
  # "FUNIL ANDROID EXTERNO" — where external Android installations stop before
  # an account exists.
  #
  # The panel already knew how many installations existed (AndroidInstallations)
  # and how the linked users converted afterwards (AndroidInstallations#user_funnel).
  # Neither could answer the question that matters while installs pile up and
  # users do not: at which step do people drop out BEFORE creating the account?
  #
  # THE UNIT IS ONE INSTALLATION, NOT ONE EVENT. Every step counts distinct
  # `installation_id`s, which is why the aggregation is a GROUP BY on
  # properties->>'installation_id': an installation that fired app_opened seven
  # times is one installation at that step, by construction and not by a filter
  # someone has to remember to write.
  #
  # Only instrumented builds are in scope. Builds below MIN_INSTRUMENTED_BUILD
  # carry no installation_id on their events and never emitted auth_screen_viewed
  # or signup_selected/login_selected, so including them would report "abandono"
  # for a step that could not physically be reached. Historical installations
  # stay in the general Android panel and are deliberately NOT mixed in here.
  #
  # NOT a device heuristic. Who is external is decided by AccountClassification
  # (identity), never by manufacturer — a Pixel is a Google device owned by a
  # real person.
  #
  # Read-only by construction: every method is a SELECT. Nothing here writes a
  # record, emits an event or backfills history.
  class AndroidFunnel
    PLATFORM = "android".freeze

    # The pre-auth instrumentation landed in build 51. The default lives in code
    # on purpose: an env missing on a server must never silently let
    # uninstrumented builds back into the funnel and read as mass abandonment.
    DEFAULT_MIN_INSTRUMENTED_BUILD = 51

    PERIODS = %w[since_instrumentation today 7d 30d].freeze
    DEFAULT_PERIOD = "since_instrumentation".freeze

    AUDIENCES = %w[external internal_test all].freeze
    DEFAULT_AUDIENCE = "external".freeze

    # Ordered steps of the pre-auth journey. Every name here exists in
    # config/analytics/events.yml — no event is invented and none is duplicated.
    #
    # `session_started` is the native session event (analytics/lifecycle.ts). Its
    # web/PWA counterpart web_session_started is deliberately absent: this funnel
    # is Android native only.
    #
    # There is no email_signup_started / email_login_started anywhere in the
    # product. The email flow emits signup_started / login_started carrying
    # method: "email", so the auth_client step already covers it.
    STAGES = [
      { key: "first_open",      label: "First open",                events: %w[app_first_open] },
      { key: "session_started", label: "Session started",           events: %w[session_started] },
      { key: "landing",         label: "Landing visualizada",       events: %w[landing_page_viewed] },
      { key: "auth_screen",     label: "Tela de autenticação",      events: %w[auth_screen_viewed] },
      { key: "auth_choice",     label: "Escolheu login/cadastro",   events: %w[signup_selected login_selected] },
      { key: "auth_provider",   label: "Tentou autenticar",         events: %w[auth_provider_clicked] },
      { key: "auth_client",     label: "Auth iniciada no cliente",  events: %w[social_login_started signup_started login_started] },
      { key: "auth_api",        label: "Auth chegou à API",         events: %w[google_auth_started android_registration_started] },
      { key: "auth_done",       label: "Auth concluída",            events: %w[google_auth_succeeded android_registration_succeeded signup_completed] },
      { key: "linked",          label: "Instalação vinculada",      events: %w[installation_link_succeeded] }
    ].freeze

    FUNNEL_EVENTS = STAGES.flat_map { |stage| stage[:events] }.uniq.freeze

    LINKED_STAGE_KEY = "linked".freeze

    COHORT_STEP_KEY = "installations".freeze
    COHORT_STEP_LABEL = "Instalações observadas".freeze

    USERS_STEP_KEY = "android_users".freeze
    USERS_STEP_LABEL = "Usuários Android criados".freeze

    NO_EVENTS_BUCKET = "no_events".freeze
    COMPLETED_BUCKET = "completed".freeze

    # Same order as the funnel, so "where did they stop" reads top to bottom.
    BUCKET_LABELS = {
      "no_events" => "Sem evento do funil",
      "stopped_first_open" => "Parou após first open",
      "stopped_session_started" => "Parou após iniciar sessão",
      "stopped_landing" => "Parou após a landing",
      "stopped_auth_screen" => "Viu auth e não escolheu",
      "stopped_auth_choice" => "Escolheu e não clicou no auth",
      "stopped_auth_provider" => "Clicou e não iniciou auth",
      "stopped_auth_client" => "Iniciou no cliente e não chegou à API",
      "stopped_auth_api" => "Chegou à API e não concluiu",
      "stopped_auth_done" => "Autenticou e não vinculou",
      "completed" => "Vinculada"
    }.freeze

    BUCKET_KEYS = BUCKET_LABELS.keys.freeze

    STEP_DEFINITION = "android_prelaunch_funnel_step_v1".freeze
    DROP_DEFINITION = "android_prelaunch_funnel_drop_v1".freeze

    DEFAULT_PER_PAGE = 50
    MAX_PER_PAGE = 200

    INSTRUMENTATION_NOTE =
      "Funil detalhado disponível somente após a ativação da instrumentação pré-auth, " \
      "a partir do build %<build>d. Dados históricos permanecem na visão geral e não são " \
      "misturados aqui.".freeze

    ANONYMOUS_CLASSIFICATION_NOTE =
      "Instalação sem usuário é contada como externa. Uma execução do Google Test Lab que " \
      "instala, navega e não cria conta é indistinguível de um usuário externo anônimo — " \
      "só é excluída quando há evidência segura de identidade.".freeze

    UNIT_NOTE =
      "A unidade de cada etapa é installation_id distinto. Eventos repetidos não somam. " \
      "A etapa de usuários criados é medida em usuários e nunca em instalações.".freeze

    CONFLICT_NOTE =
      "installation_link_failed com conflict indica um aparelho já vinculado a outra conta. " \
      "Isso aparece como 'autenticou e não vinculou' e NÃO explica o volume de instalações " \
      "anônimas — as duas coisas são medidas separadamente.".freeze

    # The event's link_result vocabulary (Observability::Events::LINK_RESULTS),
    # reached from the persisted failure code so the panel speaks one language.
    LINK_RESULT_BY_FAILURE_CODE = {
      "user_conflict" => "conflict",
      "installation_not_found" => "not_found"
    }.freeze

    class << self
      # Read at call time, never frozen into a constant at boot: the server can
      # move the threshold without a deploy, and an absent/invalid value falls
      # back to the code default instead of disabling the cut.
      def min_instrumented_build
        raw = ENV["ANDROID_FUNNEL_MIN_BUILD"].to_s.strip
        raw.match?(/\A\d+\z/) ? Integer(raw) : DEFAULT_MIN_INSTRUMENTED_BUILD
      end
    end

    def initialize(period: nil, build: nil, audience: nil)
      @period = PERIODS.include?(period.to_s) ? period.to_s : DEFAULT_PERIOD
      @audience = AUDIENCES.include?(audience.to_s) ? audience.to_s : DEFAULT_AUDIENCE
      @build = build.to_s.strip.match?(/\A\d{1,9}\z/) ? Integer(build.to_s.strip) : nil
    end

    attr_reader :period, :audience, :build

    def call
      {
        source: "app_installations + product_analytics_events",
        generated_at: ReportingTime.now.iso8601,
        filters: { period: period, build: build, audience: audience },
        definitions: definitions,
        cohort: cohort_summary,
        available_builds: available_builds,
        steps: steps,
        biggest_drop: biggest_drop,
        stage_buckets: stage_buckets,
        link_failures: link_failures
      }
    end

    # Investigation list: the installations whose last observed step is `stage`.
    def installations(stage:, page: 1, per: nil)
      bucket = BUCKET_KEYS.include?(stage.to_s) ? stage.to_s : nil
      return empty_list(stage) if bucket.nil?

      ids = states.values.select { |state| state[:bucket] == bucket }
                  .sort_by { |state| state[:created_at] || Time.at(0) }
                  .reverse
                  .map { |state| state[:installation_id] }

      page = [ page.to_i, 1 ].max
      per = (per.presence&.to_i || DEFAULT_PER_PAGE).clamp(1, MAX_PER_PAGE)
      slice = ids.slice((page - 1) * per, per) || []

      {
        stage: bucket,
        label: BUCKET_LABELS[bucket],
        total: ids.size,
        page: page,
        per: per,
        installations: rows_for(slice)
      }
    end

    private

    def min_build
      @min_build ||= self.class.min_instrumented_build
    end

    def numeric_build
      "(#{AppInstallation::NUMERIC_BUILD_SQL})"
    end

    # Window cut in the REPORTING zone (America/Sao_Paulo), never in Time.zone
    # (UTC here): an install at 23:30 local is 02:30Z the next day, and cutting
    # "hoje" in UTC would place it on the wrong day for the person who used it.
    # "since_instrumentation" has no lower date bound on purpose — the build
    # threshold IS the instrumentation boundary.
    def window
      return @window if defined?(@window)

      now = ReportingTime.now
      @window =
        case period
        when "today" then now.beginning_of_day..now
        when "7d" then (now.beginning_of_day - 6.days)..now
        when "30d" then (now.beginning_of_day - 29.days)..now
        end
    end

    # ------------------------------------------------------------------ cohort

    # Every Android installation on an instrumented build, before the audience
    # filter. Installations whose app_build is absent or non-numeric are NOT
    # here: there is no way to claim they are >= the threshold. They are counted
    # and reported in `cohort.excluded` so the panel stays reconcilable.
    def instrumented_scope
      scope = AppInstallation.for_platform(PLATFORM)
                             .where("#{numeric_build} >= ?", min_build)
      scope = scope.where("#{numeric_build} = ?", build) if build
      scope = scope.where(created_at: window) if window
      scope
    end

    def cohort_scope
      @cohort_scope ||=
        case audience
        when "internal_test" then instrumented_scope.where(id: non_external_scope.select(:id))
        when "all" then instrumented_scope
        else instrumented_scope.where.not(id: non_external_scope.select(:id))
        end
    end

    # Non-external = linked to an internal/automated-test account, OR anonymous
    # with safe evidence that a robot drove it (an event of that installation
    # carrying an automated-test user). Anything else stays external: guessing
    # would be inventing a classification.
    def non_external_scope
      scope = instrumented_scope.where(user_id: non_external_user_ids)
      ids = automated_test_evidence_ids
      return scope if ids.empty?

      scope.or(instrumented_scope.where(installation_id: ids))
    end

    def non_external_user_ids
      @non_external_user_ids ||=
        AccountClassification.internal_scope(User.all).pluck(:id) |
        AccountClassification.automated_test_scope(User.all).pluck(:id)
    end

    # The only "safe evidence" available for an installation that never linked:
    # some event of it was attributed to a Test Lab account. Bounded by the
    # (user_id, occurred_at) index — the robot account set is tiny.
    def automated_test_evidence_ids
      @automated_test_evidence_ids ||=
        ProductAnalyticsEvent
          .where(user_id: AccountClassification.automated_test_scope(User.all).select(:id))
          .where("product_analytics_events.properties->>'installation_id' IS NOT NULL")
          .distinct
          .pluck(Arel.sql("product_analytics_events.properties->>'installation_id'"))
          .compact
    end

    def cohort_summary
      {
        installations: states.size,
        excluded: { missing_or_invalid_build: excluded_build_count }
      }
    end

    # Reported, not hidden: the total of the panel must reconcile with the total
    # of Android installations, and "invisible exclusion" is how a funnel starts
    # lying without anyone noticing.
    def excluded_build_count
      scope = AppInstallation.for_platform(PLATFORM)
      scope = scope.where(created_at: window) if window
      scope.where("app_build IS NULL OR btrim(app_build) = '' OR #{numeric_build} IS NULL").count
    end

    def available_builds
      scope = AppInstallation.for_platform(PLATFORM).where("#{numeric_build} >= ?", min_build)
      scope = scope.where(created_at: window) if window
      scope.distinct.pluck(Arel.sql(numeric_build)).compact.sort.reverse
    end

    # ------------------------------------------------------------------- state

    # One row per installation of the cohort: which steps it reached, where it
    # stopped, and its last observed event. Built from exactly two queries.
    def states
      @states ||= begin
        base = cohort_scope.pluck(:installation_id, :user_id, :created_at, :last_link_failure_code)
        events = event_aggregate

        base.each_with_object({}) do |(installation_id, user_id, created_at, failure_code), acc|
          counts = events[installation_id] || {}
          stages = STAGES.to_h do |stage|
            reached = counts["s_#{stage[:key]}"].to_i.positive?
            reached ||= linked_by_ownership?(user_id, failure_code) if stage[:key] == LINKED_STAGE_KEY
            reached &&= !unresolved_conflict?(failure_code) if stage[:key] == LINKED_STAGE_KEY
            [ stage[:key], reached ]
          end

          acc[installation_id] = {
            installation_id: installation_id,
            user_id: user_id,
            created_at: created_at,
            stages: stages,
            bucket: bucket_for(stages),
            last_event_name: counts["last_event_name"],
            last_event_at: counts["last_event_at"]
          }
        end
      end
    end

    # The central query. Aggregation happens in the database, grouped by
    # installation_id — no ProductAnalyticsEvent is ever loaded into Ruby and
    # filtered with select. The result has at most one row per installation.
    def event_aggregate
      sql = <<~SQL.squish
        SELECT e.properties->>'installation_id' AS installation_id,
               #{stage_select},
               MAX(e.occurred_at) AS last_event_at,
               (ARRAY_AGG(e.event_name ORDER BY e.occurred_at DESC))[1] AS last_event_name
        FROM product_analytics_events e
        WHERE e.event_name IN (#{quoted_funnel_events})
          AND e.properties->>'installation_id' IN (#{cohort_scope.select(:installation_id).to_sql})
          #{event_window_clause}
        GROUP BY 1
      SQL

      ApplicationRecord.connection.select_all(sql).to_a.index_by { |row| row["installation_id"] }
    end

    def stage_select
      STAGES.map do |stage|
        names = stage[:events].map { |name| ApplicationRecord.connection.quote(name) }.join(", ")
        "COUNT(*) FILTER (WHERE e.event_name IN (#{names})) AS s_#{stage[:key]}"
      end.join(", ")
    end

    def quoted_funnel_events
      FUNNEL_EVENTS.map { |name| ApplicationRecord.connection.quote(name) }.join(", ")
    end

    def event_window_clause
      return "" unless window

      ApplicationRecord.sanitize_sql_array(
        [ "AND e.occurred_at >= ? AND e.occurred_at <= ?", window.begin, window.end ]
      )
    end

    # user_id IS the link. An installation linked before the current LinkToUser
    # flow existed has no installation_link_succeeded event and is still linked —
    # reading only the event would report it as a drop-off it never was.
    def linked_by_ownership?(user_id, failure_code)
      user_id.present? && !unresolved_conflict?(failure_code)
    end

    # A device already owned by user A on which user B just signed up: B's link
    # fails with user_conflict while the row keeps A's user_id. Counting that as
    # "vinculada" would report a conversion that did not happen for the person
    # who was actually there. The code is cleared on a successful link, so its
    # presence means the LAST attempt is the one that failed.
    def unresolved_conflict?(failure_code)
      failure_code.to_s == "user_conflict"
    end

    # The furthest step observed. Reaching the last step is "completed"; anything
    # else is "stopped after <that step>"; nothing at all is "no_events".
    def bucket_for(stages)
      last = STAGES.rindex { |stage| stages[stage[:key]] }
      return NO_EVENTS_BUCKET if last.nil?
      return COMPLETED_BUCKET if STAGES[last][:key] == LINKED_STAGE_KEY

      "stopped_#{STAGES[last][:key]}"
    end

    # ------------------------------------------------------------------- steps

    def cohort_count
      states.size
    end

    def stage_counts
      @stage_counts ||= STAGES.to_h do |stage|
        [ stage[:key], states.values.count { |state| state[:stages][stage[:key]] } ]
      end
    end

    # Installation-keyed steps only, in order, used for conversions and drops.
    # The users step is spliced into the display list but never into this one:
    # a user count and an installation count must not be divided by each other.
    def installation_steps
      @installation_steps ||=
        [ [ COHORT_STEP_KEY, COHORT_STEP_LABEL, cohort_count ] ] +
        STAGES.map { |stage| [ stage[:key], stage[:label], stage_counts[stage[:key]] ] }
    end

    def steps
      rows = installation_steps.each_with_index.map do |(key, label, count), index|
        previous = index.zero? ? nil : installation_steps[index - 1]

        {
          key: key,
          label: label,
          unit: "installations",
          count: count,
          conversion_from_previous: previous && ratio(count, previous[2]),
          conversion_from_cohort: index.zero? ? nil : ratio(count, cohort_count)
        }.compact
      end

      insert_at = rows.index { |row| row[:key] == LINKED_STAGE_KEY } || rows.size
      rows.insert(insert_at, users_step)
      rows
    end

    # Reported as USERS and labelled as such. Presenting it as an installation
    # step would silently compare two different populations.
    def users_step
      {
        key: USERS_STEP_KEY,
        label: USERS_STEP_LABEL,
        unit: "users",
        count: android_users_count,
        note: "Métrica de usuários, não de instalações."
      }
    end

    def android_users_count
      scope = User.where(signup_source: PLATFORM)
      scope = scope.where(created_at: window) if window

      case audience
      when "all" then scope.count
      when "internal_test" then scope.count - AccountClassification.exclude_non_external(scope).count
      else AccountClassification.exclude_non_external(scope).count
      end
    end

    def ratio(numerator, denominator)
      MetricResult.ratio(
        numerator: numerator,
        denominator: denominator,
        definition: STEP_DEFINITION
      ).as_json
    end

    # ----------------------------------------------------------- biggest drop

    # The largest absolute loss between two consecutive installation steps.
    # Descriptive only: this is where people stop being observed, which is not
    # the same as why they stopped.
    def biggest_drop
      pairs = installation_steps.each_cons(2).map do |(from_key, from_label, from_count), (to_key, to_label, to_count)|
        { from_key: from_key, from_label: from_label, to_key: to_key, to_label: to_label,
          lost: from_count - to_count, from_count: from_count }
      end

      worst = pairs.select { |pair| pair[:lost].positive? }.max_by { |pair| pair[:lost] }
      return nil if worst.nil?

      worst.except(:from_count).merge(
        drop_rate: MetricResult.ratio(
          numerator: worst[:lost],
          denominator: worst[:from_count],
          definition: DROP_DEFINITION
        ).as_json
      )
    end

    # ----------------------------------------------------------------- buckets

    def stage_buckets
      counts = states.values.group_by { |state| state[:bucket] }.transform_values(&:size)

      BUCKET_KEYS.map do |key|
        { key: key, label: BUCKET_LABELS[key], count: counts.fetch(key, 0) }
      end
    end

    def link_failures
      cohort_scope.where.not(last_link_failure_code: [ nil, "" ])
                  .group(:last_link_failure_code)
                  .count
    end

    # -------------------------------------------------------------------- list

    def empty_list(stage)
      { stage: stage.to_s, label: nil, total: 0, page: 1, per: DEFAULT_PER_PAGE, installations: [] }
    end

    # includes(:user) so a page of rows never turns into one query per row.
    def rows_for(installation_ids)
      return [] if installation_ids.empty?

      records = AppInstallation.includes(:user)
                               .where(installation_id: installation_ids)
                               .index_by(&:installation_id)

      installation_ids.filter_map { |id| records[id] }.map { |record| row_for(record) }
    end

    def row_for(record)
      state = states[record.installation_id] || {}
      # Same notion of "linked" the funnel used, so a row can never contradict
      # the step it was listed under.
      linked = state.dig(:stages, LINKED_STAGE_KEY) || false
      owned = record.user_id.present?

      {
        installation_id: record.installation_id,
        created_at: record.created_at&.iso8601,
        first_seen_at: record.first_seen_at&.iso8601,
        last_seen_at: record.last_seen_at&.iso8601,
        app_version: record.app_version,
        app_build: record.app_build,
        device_manufacturer: record.device_manufacturer,
        device_model: record.device_model,
        operating_system: record.operating_system,
        operating_system_version: record.operating_system_version,
        last_stage: state[:bucket],
        last_stage_label: BUCKET_LABELS[state[:bucket]],
        last_event_name: state[:last_event_name],
        last_event_at: state[:last_event_at],
        linked: linked,
        link_result: link_result_for(record, owned),
        last_link_failure_code: record.last_link_failure_code,
        link_attempts_count: record.link_attempts_count,
        # Identity is exposed only once the installation has an owner, matching
        # what the Usuários table of the admin already shows. On a conflict row
        # the owner is the PREVIOUS account, which is exactly what makes the case
        # diagnosable. Anonymous rows carry no identity at all — and no token,
        # credential or raw properties blob ever leaves this service.
        user_id: owned ? record.user_id : nil,
        email: owned ? record.user&.email : nil
      }
    end

    def link_result_for(record, linked)
      code = record.last_link_failure_code.presence
      return linked ? "linked" : nil if code.nil?

      LINK_RESULT_BY_FAILURE_CODE.fetch(code, "error")
    end

    # ------------------------------------------------------------- definitions

    def definitions
      {
        min_instrumented_build: min_build,
        period: period,
        window_start: window&.begin&.iso8601,
        window_end: window&.end&.iso8601,
        stage_definitions: STAGES.map { |stage| stage.slice(:key, :label, :events) },
        bucket_order: BUCKET_KEYS,
        instrumentation_note: format(INSTRUMENTATION_NOTE, build: min_build),
        unit_note: UNIT_NOTE,
        anonymous_classification_note: ANONYMOUS_CLASSIFICATION_NOTE,
        conflict_note: CONFLICT_NOTE
      }
    end
  end
end
