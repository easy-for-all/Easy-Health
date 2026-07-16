module Analytics
  # Single source of truth for the timezone used in analytics reporting.
  #
  # The app runs in UTC but the user base is Brazilian (UTC-3). Daily cohort
  # cuts and retention windows must be computed in the reporting zone, otherwise
  # a workout done at 22h local lands on the next UTC day and distorts D1/D7/D30.
  module ReportingTime
    DEFAULT_ZONE = "America/Sao_Paulo".freeze

    module_function

    def zone
      ActiveSupport::TimeZone[ENV.fetch("ANALYTICS_REPORTING_TIMEZONE", DEFAULT_ZONE)] ||
        ActiveSupport::TimeZone[DEFAULT_ZONE]
    end

    def now
      zone.now
    end

    def today
      now.to_date
    end

    # SQL fragment that converts a UTC timestamp column to a DATE in the
    # reporting zone. Use in place of raw DATE(column).
    #   local_date_sql("workout_sessions.completed_at") =>
    #   "(workout_sessions.completed_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Sao_Paulo')::date"
    def local_date_sql(column)
      "(#{column} AT TIME ZONE 'UTC' AT TIME ZONE '#{zone.tzinfo.name}')::date"
    end

    # Whether a cohort registered `days` ago has had enough observation time to
    # be measured (e.g. a D7 cohort needs 7 full days). Used for cohort_maturity.
    def cohort_mature?(cohort_start, days)
      return false if cohort_start.nil?

      cohort_start.to_date <= (today - days)
    end
  end
end
