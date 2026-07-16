module Analytics
  # "Impacto do app Android" (Fase 15) — the central observational analysis.
  #
  # Cohorts users by activation_platform (the platform of their FIRST product
  # event: android / web / pwa). A user is never reclassified by a later session,
  # so cross-platform behaviour does not blur the cohort.
  #
  # Every cell is a MetricResult (numerator/denominator/status/cohort_maturity),
  # so small early cohorts surface as insufficient_sample rather than misleading
  # percentages. activation_platform is populated going forward, so cohorts grow
  # from the deploy date (coverage = event_tracked).
  #
  # This is OBSERVATIONAL: users who install the app may be more engaged to begin
  # with. Selection bias is not removed — see the note returned to the UI.
  class PlatformComparison
    COHORTS = %w[android web pwa].freeze

    SELECTION_BIAS_NOTE =
      "Usuários que escolhem instalar o aplicativo podem ser naturalmente mais " \
      "engajados. A comparação observacional não elimina viés de seleção.".freeze

    def call
      {
        cohorts: COHORTS.index_with { |platform| cohort_metrics(platform) },
        note: SELECTION_BIAS_NOTE,
        coverage: "event_tracked",
        generated_at: ReportingTime.now.iso8601
      }
    end

    private

    def base(platform)
      User.reportable.where(activation_platform: platform)
    end

    def cohort_metrics(platform)
      users = base(platform)
      size = users.count

      created  = users.where(id: WorkoutPlan.select(:user_id)).count
      completed = users.where(id: completed_session_user_ids).count
      activated_24h = users.where(id: activated_24h_user_ids).count
      retained_d7 = retention_value_d7(users)

      {
        cohort_size: size,
        created_workout: MetricResult.ratio(numerator: created, denominator: size, definition: "created_workout_v1"),
        completed_workout: MetricResult.ratio(numerator: completed, denominator: size, definition: "first_workout_conversion_v1"),
        activation_24h: MetricResult.ratio(numerator: activated_24h, denominator: size, definition: "activation_24h_v1"),
        retention_value_d7: retained_d7
      }
    end

    def completed_session_user_ids
      WorkoutSession.where(completion_status: "completed").select(:user_id)
    end

    # Users whose FIRST completed workout happened within 24h of signup (created_at).
    def activated_24h_user_ids
      WorkoutSession
        .where(completion_status: "completed")
        .joins("INNER JOIN users u ON u.id = workout_sessions.user_id")
        .where("workout_sessions.completed_at <= u.created_at + INTERVAL '24 hours'")
        .distinct
        .pluck(:user_id)
    end

    # D7 value retention within the cohort, mature users only (created >= 7d ago).
    def retention_value_d7(users)
      mature = users.where("users.created_at <= ?", 7.days.ago)
      base_count = mature.count

      completed_local = ReportingTime.local_date_sql("workout_sessions.completed_at")
      created_local   = ReportingTime.local_date_sql("users.created_at")
      retained = WorkoutSession
        .where(completion_status: "completed")
        .where(user_id: mature.select(:id))
        .joins("INNER JOIN users ON users.id = workout_sessions.user_id")
        .where("#{completed_local} BETWEEN (#{created_local} + 7) AND (#{created_local} + 8)")
        .distinct.count(:user_id)

      MetricResult.ratio(
        numerator: retained,
        denominator: base_count,
        definition: "retention_value_d7_v1",
        cohort_maturity: base_count.zero? ? "immature" : "mature"
      )
    end
  end
end
