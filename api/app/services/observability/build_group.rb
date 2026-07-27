module Observability
  # Buckets an Android app_build into stable descriptive cohorts.
  #
  # Why cohorts and not the raw build number: a build label is unbounded (every
  # CI run bumps ANDROID_VERSION_CODE), so grouping by it would grow a new
  # series per release forever. These labels are release metadata only; they do
  # not decide whether an installation is eligible for reconciliation.
  #
  # ::SQL mirrors this logic for aggregate queries and for the BI views, reusing
  # AppInstallation::NUMERIC_BUILD_SQL so a malformed app_build can never blow up
  # an int cast.
  module BuildGroup
    UNKNOWN  = "unknown".freeze  # blank or non-numeric build
    REPORTED = "reported".freeze # numeric build, no configured current floor matched
    CURRENT  = "current".freeze  # at or above the optional descriptive current floor

    ALL = [ UNKNOWN, REPORTED, CURRENT ].freeze

    module_function

    def current_build_min
      Observability::Config.current_build_min
    end

    def for(app_build)
      numeric = numeric_build(app_build)
      return UNKNOWN if numeric.nil?
      floor = current_build_min
      return CURRENT if floor && numeric >= floor

      REPORTED
    end

    def numeric_build(app_build)
      raw = app_build.to_s.strip
      return nil unless raw.match?(/\A[0-9]{1,9}\z/)

      raw.to_i
    end

    # SQL CASE producing the same labels, for GROUP BY in checks and views.
    # `column` lets the BI views point at a differently-named source column.
    def sql(column: "app_build")
      numeric = AppInstallation::NUMERIC_BUILD_SQL.gsub("app_build", column)
      floor = current_build_min

      return <<~SQL.squish unless floor
        CASE
          WHEN (#{numeric}) IS NULL THEN '#{UNKNOWN}'
          ELSE '#{REPORTED}'
        END
      SQL

      <<~SQL.squish
        CASE
          WHEN (#{numeric}) IS NULL THEN '#{UNKNOWN}'
          WHEN (#{numeric}) >= #{floor} THEN '#{CURRENT}'
          ELSE '#{REPORTED}'
        END
      SQL
    end
  end
end
