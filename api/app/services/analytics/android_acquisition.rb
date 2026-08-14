module Analytics
  # "AQUISIÇÃO ANDROID" — Google Ads attribution beside real product behaviour.
  #
  # TWO UNIVERSES, NEVER MIXED. The Google Ads block is what Google attributed
  # to the campaign, on Google's reporting dates and attribution rules. The
  # EasyHealth block is what our own database recorded, grouped by the local
  # (America/Sao_Paulo) date the Android account was created. They are placed
  # side by side because that is useful, and never divided by each other because
  # that would be a user-level attribution we do not have.
  #
  # NEVER CALLS GOOGLE. This runs on every Admin page load, so it reads only
  # google_ads_daily_metrics — the cache written by the hourly sync. A Google
  # outage therefore cannot slow down or break the panel; it can only make the
  # cached numbers older, which is reported as such.
  #
  # Read-only by construction: every method is a SELECT.
  class AndroidAcquisition
    PLATFORM = "android".freeze

    HEARTBEAT_KEY = "google_ads_acquisition_sync".freeze

    PERIODS = %w[today yesterday 7d 30d custom].freeze
    DEFAULT_PERIOD = "7d".freeze
    MAX_CUSTOM_DAYS = 180

    # A cohort that registered less than this ago has not had time to train yet.
    # Shown, but flagged — a two-hour-old cohort at 0% is not a conversion rate.
    COHORT_MATURITY_DAYS = 1

    # The sync is expected hourly; twice that is the point at which the cache
    # stops being "the current picture".
    STALE_AFTER = 2.hours

    ADS_NOTE =
      "Google Ads mostra resultados atribuídos à campanha segundo as regras de atribuição e as " \
      "datas de reporting do Google.".freeze

    PRODUCT_NOTE =
      "EasyHealth mostra comportamento registrado diretamente no produto, agrupado pela data de " \
      "criação da conta Android (America/Sao_Paulo).".freeze

    COMPARISON_NOTE =
      "Os números são complementares e não precisam ser idênticos. Uma diferença entre os dois " \
      "blocos não é, por si só, erro, perda ou tracking quebrado.".freeze

    NO_CROSS_RATE_NOTE =
      "Não há taxa entre os dois blocos: dividir instalações atribuídas por contas EasyHealth " \
      "seria uma atribuição por usuário que esta versão não faz.".freeze

    COHORT_NOTE =
      "Cada linha conta as contas Android criadas naquele dia e, dessas MESMAS contas, quantas " \
      "depois criaram, iniciaram e concluíram um treino.".freeze

    STARTED_NOTE =
      "Iniciou = existe sessão de treino com started_at preenchido. Concluiu = existe sessão com " \
      "completion_status 'completed'.".freeze

    SYNC_LABELS = {
      "ok" => "Dados Google Ads atualizados",
      "stale" => "Dados Google Ads desatualizados",
      "error" => "Última sincronização Google Ads falhou",
      "never_synced" => "Google Ads ainda não sincronizado",
      "not_configured" => "Google Ads não configurado"
    }.freeze

    class InvalidRange < StandardError; end

    def initialize(period: nil, start_date: nil, end_date: nil)
      @period = PERIODS.include?(period.to_s) ? period.to_s : DEFAULT_PERIOD
      @requested_start = start_date
      @requested_end = end_date
      resolve_range!
    end

    attr_reader :period, :start_date, :end_date

    def call
      {
        source: "google_ads_daily_metrics + users/workout_plans/workout_sessions",
        generated_at: ReportingTime.now.iso8601,
        filters: { period: period, start_date: start_date.iso8601, end_date: end_date.iso8601 },
        sync: sync_status,
        ads: ads_summary,
        easyhealth: product_summary,
        daily: daily_rows,
        definitions: definitions
      }
    end

    private

    # --------------------------------------------------------------- date range

    def resolve_range!
      today = ReportingTime.today

      case period
      when "today"
        @start_date = @end_date = today
      when "yesterday"
        @start_date = @end_date = today - 1
      when "30d"
        @start_date = today - 29
        @end_date = today
      when "custom"
        @start_date = parse_date(@requested_start)
        @end_date = parse_date(@requested_end)
        raise InvalidRange, "Informe start e end no formato AAAA-MM-DD." if @start_date.nil? || @end_date.nil?
        raise InvalidRange, "A data inicial não pode ser depois da final." if @start_date > @end_date
        if (@end_date - @start_date).to_i >= MAX_CUSTOM_DAYS
          raise InvalidRange, "Intervalo máximo de #{MAX_CUSTOM_DAYS} dias."
        end
      else
        @start_date = today - 6
        @end_date = today
      end
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # Cohort boundaries are cut in the reporting zone: an account created at
    # 23:30 local is 02:30Z the next day, and a UTC cut would file it under the
    # wrong day for the person who created it.
    def cohort_window
      @cohort_window ||= begin
        zone = ReportingTime.zone
        zone.parse(start_date.iso8601).beginning_of_day..zone.parse(end_date.iso8601).end_of_day
      end
    end

    # ------------------------------------------------------------------- sync

    def campaign_id
      @campaign_id ||= ::GoogleAds::AndroidAcquisitionSync.campaign_id
    end

    def configured?
      ::GoogleAds::AndroidAcquisitionSync.configured?
    end

    def heartbeat
      return @heartbeat if defined?(@heartbeat)

      @heartbeat = ObservabilityHeartbeat.find_by(key: HEARTBEAT_KEY)
    end

    def last_synced_at
      return @last_synced_at if defined?(@last_synced_at)

      scope = GoogleAdsDailyMetric.all
      scope = scope.for_campaign(campaign_id) if campaign_id.present?
      @last_synced_at = scope.maximum(:synced_at)
    end

    # Reuses the existing heartbeat infrastructure for "did the cron run and did
    # it succeed", and the cache's own MAX(synced_at) for "how old is the data".
    # No new status table: the two together already answer the question.
    #
    # "Falhou" is only ever claimed when there is real evidence of a failure.
    # Data that is merely old reports as desatualizado, not as an outage.
    def sync_status
      status =
        if !configured?
          "not_configured"
        elsif last_synced_at.nil?
          "never_synced"
        elsif failing?
          "error"
        elsif last_synced_at < STALE_AFTER.ago
          "stale"
        else
          "ok"
        end

      {
        status: status,
        label: SYNC_LABELS[status],
        last_synced_at: last_synced_at&.iso8601,
        last_succeeded_at: heartbeat&.last_succeeded_at&.iso8601,
        last_failed_at: heartbeat&.last_failed_at&.iso8601,
        last_error_code: heartbeat&.last_error_code,
        consecutive_failures: heartbeat&.consecutive_failures,
        campaign_id: campaign_id,
        missing_configuration: configured? ? [] : ::GoogleAds::AndroidAcquisitionSync.missing_configuration
      }
    end

    def failing?
      return false if heartbeat.nil? || heartbeat.last_failed_at.nil?

      heartbeat.last_succeeded_at.nil? || heartbeat.last_failed_at > heartbeat.last_succeeded_at
    end

    # -------------------------------------------------------------- google ads

    def ads_scope
      @ads_scope ||= begin
        scope = GoogleAdsDailyMetric.between(start_date, end_date)
        # Scoped to the configured campaign so a second campaign's rows can
        # never be silently added to these totals.
        campaign_id.present? ? scope.for_campaign(campaign_id) : scope.none
      end
    end

    def ads_daily
      @ads_daily ||= ads_scope.order(date: :desc).to_a
    end

    def ads_summary
      cost_micros = ads_daily.sum { |row| row.cost_micros.to_i }
      installs = ads_daily.sum { |row| row.installs.to_d }
      sign_ups = ads_daily.sum { |row| row.sign_ups.to_d }

      ads_payload(
        cost_micros: cost_micros,
        impressions: ads_daily.sum { |row| row.impressions.to_i },
        clicks: ads_daily.sum { |row| row.clicks.to_i },
        installs: installs,
        sign_ups: sign_ups
      ).merge(configured: configured?, days_with_data: ads_daily.size)
    end

    def ads_payload(cost_micros:, impressions:, clicks:, installs:, sign_ups:)
      cost_brl = cost_micros.to_i / 1_000_000.0

      {
        cost_micros: cost_micros.to_i,
        cost_brl: cost_brl.round(2),
        impressions: impressions.to_i,
        clicks: clicks.to_i,
        installs: installs.to_d.to_f,
        sign_ups: sign_ups.to_d.to_f,
        # nil, never 0: "R$ 0,00 por instalação" would read as free acquisition
        # when what actually happened is that there is no denominator yet.
        cpi_brl: safe_divide(cost_brl, installs)&.round(2),
        cpa_signup_brl: safe_divide(cost_brl, sign_ups)&.round(2),
        install_to_signup: ads_ratio(sign_ups, installs)
      }
    end

    def safe_divide(numerator, denominator)
      denominator = denominator.to_d
      return nil if denominator.zero?

      numerator.to_d.to_f / denominator.to_f
    end

    # Deliberately not a MetricResult: attributed conversions are decimals and
    # carry no cohort or sample size, so the sample-based statuses of
    # MetricResult would be meaningless here.
    def ads_ratio(numerator, denominator)
      value = safe_divide(numerator, denominator)
      return nil if value.nil?

      {
        value: (value * 100).round(1),
        numerator: numerator.to_d.to_f,
        denominator: denominator.to_d.to_f
      }
    end

    # -------------------------------------------------------------- easyhealth

    # One grouped query for the whole cohort table. Each user is evaluated once,
    # with EXISTS subqueries — no per-day or per-user follow-up query.
    def cohort_rows
      @cohort_rows ||= begin
        scope = AccountClassification.exclude_non_external(User.where(signup_source: PLATFORM))
        day = ReportingTime.local_date_sql("u.created_at")

        bounds = ApplicationRecord.sanitize_sql_array(
          [ "u.created_at >= ? AND u.created_at <= ?", cohort_window.begin, cohort_window.end ]
        )

        sql = <<~SQL.squish
          SELECT c.day AS day,
                 COUNT(*) AS accounts,
                 COUNT(*) FILTER (WHERE c.created_workout) AS created_workout,
                 COUNT(*) FILTER (WHERE c.started_workout) AS started_workout,
                 COUNT(*) FILTER (WHERE c.completed_workout) AS completed_workout,
                 COUNT(*) FILTER (WHERE c.completed_workout AND NOT c.started_workout)
                   AS completed_without_started
          FROM (
            SELECT #{day} AS day,
                   EXISTS (
                     SELECT 1 FROM workout_plans wp WHERE wp.user_id = u.id
                   ) AS created_workout,
                   EXISTS (
                     SELECT 1 FROM workout_sessions ws
                     WHERE ws.user_id = u.id AND ws.started_at IS NOT NULL
                   ) AS started_workout,
                   EXISTS (
                     SELECT 1 FROM workout_sessions ws
                     WHERE ws.user_id = u.id AND ws.completion_status = 'completed'
                   ) AS completed_workout
            FROM users u
            WHERE u.id IN (#{scope.select(:id).to_sql}) AND #{bounds}
          ) c
          GROUP BY c.day
          ORDER BY c.day DESC
        SQL

        ApplicationRecord.connection.select_all(sql).to_a.map do |row|
          {
            date: row["day"].to_s,
            accounts: row["accounts"].to_i,
            created_workout: row["created_workout"].to_i,
            started_workout: row["started_workout"].to_i,
            completed_workout: row["completed_workout"].to_i,
            completed_without_started: row["completed_without_started"].to_i
          }
        end
      end
    end

    def product_summary
      accounts = cohort_rows.sum { |row| row[:accounts] }
      created = cohort_rows.sum { |row| row[:created_workout] }
      started = cohort_rows.sum { |row| row[:started_workout] }
      completed = cohort_rows.sum { |row| row[:completed_workout] }

      product_payload(accounts, created, started, completed, maturity_for(end_date)).merge(
        data_quality: {
          completed_without_started: cohort_rows.sum { |row| row[:completed_without_started] }
        }
      )
    end

    def product_payload(accounts, created, started, completed, maturity)
      {
        accounts: accounts,
        created_workout: created,
        started_workout: started,
        completed_workout: completed,
        cohort_maturity: maturity,
        account_to_created: cohort_ratio(created, accounts, "android_acquisition_account_to_created_v1", maturity),
        created_to_started: cohort_ratio(started, created, "android_acquisition_created_to_started_v1", maturity),
        started_to_completed: cohort_ratio(completed, started, "android_acquisition_started_to_completed_v1", maturity)
      }
    end

    def cohort_ratio(numerator, denominator, definition, maturity)
      MetricResult.ratio(
        numerator: numerator,
        denominator: denominator,
        definition: definition,
        cohort_maturity: maturity
      ).as_json
    end

    def maturity_for(date)
      ReportingTime.cohort_mature?(date, COHORT_MATURITY_DAYS) ? "mature" : "immature"
    end

    # ------------------------------------------------------------------- table

    # Both universes on one line, keyed by the calendar date each one uses. The
    # dates are aligned for reading, not reconciled: see the notes.
    def daily_rows
      ads_by_date = ads_daily.index_by { |row| row.date.to_s }
      cohort_by_date = cohort_rows.index_by { |row| row[:date] }

      dates = (ads_by_date.keys | cohort_by_date.keys).sort.reverse

      dates.map do |date|
        ads_row = ads_by_date[date]
        cohort = cohort_by_date[date] || {
          accounts: 0, created_workout: 0, started_workout: 0, completed_workout: 0
        }
        maturity = maturity_for(Date.parse(date))

        {
          date: date,
          ads: ads_row_payload(ads_row),
          easyhealth: product_payload(
            cohort[:accounts], cohort[:created_workout],
            cohort[:started_workout], cohort[:completed_workout], maturity
          )
        }
      end
    end

    def ads_row_payload(row)
      return nil if row.nil?

      ads_payload(
        cost_micros: row.cost_micros.to_i,
        impressions: row.impressions.to_i,
        clicks: row.clicks.to_i,
        installs: row.installs.to_d,
        sign_ups: row.sign_ups.to_d
      )
    end

    def definitions
      {
        timezone: ReportingTime.zone.tzinfo.name,
        cohort_maturity_days: COHORT_MATURITY_DAYS,
        max_custom_days: MAX_CUSTOM_DAYS,
        ads_note: ADS_NOTE,
        product_note: PRODUCT_NOTE,
        comparison_note: COMPARISON_NOTE,
        no_cross_rate_note: NO_CROSS_RATE_NOTE,
        cohort_note: COHORT_NOTE,
        started_note: STARTED_NOTE
      }
    end
  end
end
