module Api
  module V1
    class AdminController < BaseController
      before_action :require_admin!

      def stats
        total_users = User.count

        # Trial metrics
        trial_active_count  = User.where("trial_ends_at > ?", Time.current).count
        trial_expired_count = User.where("trial_ends_at <= ?", Time.current)
                                  .left_joins(:subscription)
                                  .where("subscriptions.status IS NULL OR subscriptions.status NOT IN ('active','trialing')")
                                  .count
        trial_expiring_24h_count = User.where(trial_ends_at: Time.current..24.hours.from_now)
                                       .left_joins(:subscription)
                                       .where("subscriptions.status IS NULL OR subscriptions.status NOT IN ('active','trialing')")
                                       .count
        trial_expiring_48h_count = User.where(trial_ends_at: Time.current..48.hours.from_now)
                                       .left_joins(:subscription)
                                       .where("subscriptions.status IS NULL OR subscriptions.status NOT IN ('active','trialing')")
                                       .count
        premium_count       = User.joins(:subscription).where(subscriptions: { status: "active" }).count

        # Legacy Stripe trialing
        stripe_trialing_count = User.joins(:subscription).where(subscriptions: { status: "trialing" }).count

        # Workout engagement
        users_created_workouts   = User.joins(:workout_plans).distinct.count
        # Single definition of "executed a workout": a COMPLETED session.
        # (Previously joins(:workout_sessions) also counted in_progress/cancelled,
        # yielding a different number from OnboardingAnalyticsService.)
        users_completed_workouts = User.joins(:workout_sessions)
                                       .where(workout_sessions: { completion_status: "completed" })
                                       .distinct.count
        users_plan_not_started   = User.joins(:workout_plans)
                                       .left_joins(:workout_sessions)
                                       .where(workout_sessions: { id: nil })
                                       .distinct
                                       .count

        users_with_2plus_sessions = WorkoutSession.group(:user_id).having("COUNT(*) >= 2").count.size
        users_with_3plus_sessions = WorkoutSession.group(:user_id).having("COUNT(*) >= 3").count.size

        active_last_7_days  = WorkoutSession.where("completed_at > ?", 7.days.ago).distinct.count(:user_id)
        active_last_30_days = WorkoutSession.where("completed_at > ?", 30.days.ago).distinct.count(:user_id)
        active_segment_counts = UserSegment.active.group(:segment_name).count
        make_events_today = UserEvent.where(make_delivery_status: "delivered", created_at: Time.current.beginning_of_day..).count
        make_events_failed = UserEvent.where(make_delivery_status: "failed").count
        recent_relationship_events = UserEvent.order(created_at: :desc).limit(10).map do |event|
          {
            id: event.id,
            user_id: event.user_id,
            event_name: event.event_name,
            occurred_at: event.occurred_at&.iso8601,
            make_delivery_status: event.make_delivery_status
          }
        end
        recent_activation_events = recent_activation_events_rows

        # Retention D1/D7/D30 — reportable base only; a cohort must have had N
        # full days of observation to be in the denominator (cohort maturity is
        # implicit in the "created_at <= N.days.ago" cut). Calendar days are
        # computed in the reporting timezone, not raw UTC DATE() (see
        # Analytics::ReportingTime), so a 22h-local workout counts on the right
        # local day for a Brazilian user base.
        # Fully-qualified (::Analytics) to escape the Api::V1::Analytics namespace
        # created by app/controllers/api/v1/analytics/: an unqualified
        # `Analytics::` resolves to Api::V1::Analytics and raises NameError.
        completed_local = ::Analytics::ReportingTime.local_date_sql("workout_sessions.completed_at")
        created_local   = ::Analytics::ReportingTime.local_date_sql("users.created_at")

        d1_base    = User.reportable.where("users.created_at <= ?", 1.day.ago).count
        d7_base    = User.reportable.where("users.created_at <= ?", 7.days.ago).count
        d30_base   = User.reportable.where("users.created_at <= ?", 30.days.ago).count

        retained_on = lambda do |from_day, to_day|
          WorkoutSession
            .where(completion_status: "completed")
            .joins("INNER JOIN users ON users.id = workout_sessions.user_id")
            .merge(User.reportable)
            .where("#{completed_local} BETWEEN (#{created_local} + #{from_day}) AND (#{created_local} + #{to_day})")
            .distinct.count(:user_id)
        end

        d1_retained  = retained_on.call(1, 1)
        d7_retained  = retained_on.call(7, 8)
        d30_retained = retained_on.call(30, 31)

        retention_detail = {
          d1:  ::Analytics::MetricResult.ratio(numerator: d1_retained, denominator: d1_base, definition: "retention_value_d1_v1"),
          d7:  ::Analytics::MetricResult.ratio(numerator: d7_retained, denominator: d7_base, definition: "retention_value_d7_v1"),
          d30: ::Analytics::MetricResult.ratio(numerator: d30_retained, denominator: d30_base, definition: "retention_value_d30_v1")
        }

        # Conversion funnels
        users_subscribed = User.joins(:subscription)
                               .where("subscriptions.status IN ('active','trialing')")
                               .count

        # Percentages are clamped to [0,100]: instrumentation gaps must never
        # surface as a negative drop-off or an impossible >100% conversion.
        pct = ->(num, den) { den > 0 ? (num.to_f / den * 100).round(1).clamp(0.0, 100.0) : 0 }
        conversion_trial_to_subscription     = pct.call(users_subscribed, total_users)
        conversion_signup_to_workout_created = pct.call(users_created_workouts, total_users)
        conversion_plan_to_session           = pct.call(users_completed_workouts, users_created_workouts)
        conversion_session_to_subscription   = pct.call(users_subscribed, users_completed_workouts)

        onboarding_analytics = OnboardingAnalyticsService.new(
          period: params[:onboarding_period],
          flow: params[:onboarding_flow],
          status: params[:onboarding_status]
        ).call

        render json: {
          # Totals
          total_users: total_users,

          # Trial / subscription status
          trial_active_count: trial_active_count,
          trial_expired_count: trial_expired_count,
          trial_expiring_24h_count: trial_expiring_24h_count,
          trial_expiring_48h_count: trial_expiring_48h_count,
          trial_expired_without_subscription_count: trial_expired_count,
          premium_count: premium_count,
          stripe_trialing_count: stripe_trialing_count,

          # Workout engagement
          users_created_workouts: users_created_workouts,
          users_completed_workouts: users_completed_workouts,
          users_plan_not_started: users_plan_not_started,
          users_with_2plus_sessions: users_with_2plus_sessions,
          users_with_3plus_sessions: users_with_3plus_sessions,

          # Activity
          active_last_7_days: active_last_7_days,
          active_last_30_days: active_last_30_days,
          inactive_3_days_count: active_segment_counts["inactive_3_days"].to_i,
          inactive_7_days_count: active_segment_counts["inactive_7_days"].to_i,
          inactive_15_days_count: active_segment_counts["inactive_15_days"].to_i,
          churn_risk_count: active_segment_counts["churn_risk"].to_i,
          completed_partial_recently_count: active_segment_counts["completed_partial_recently"].to_i,
          make_events_delivered_today: make_events_today,
          make_events_failed: make_events_failed,
          recent_relationship_events: recent_relationship_events,
          recent_activation_events: recent_activation_events,

          # Retention (legacy numeric keys kept for the current UI)
          retention_d1: retention_detail[:d1].value,
          retention_d7: retention_detail[:d7].value,
          retention_d30: retention_detail[:d30].value,
          # Auditable retention with numerator/denominator/status/maturity
          retention_detail: retention_detail.transform_values(&:as_json),

          # Conversion funnels (%)
          conversion_trial_to_subscription: conversion_trial_to_subscription,
          conversion_signup_to_workout_created: conversion_signup_to_workout_created,
          conversion_plan_to_session: conversion_plan_to_session,
          conversion_session_to_subscription: conversion_session_to_subscription,

          # Totals for legacy compatibility
          total_workout_plans: WorkoutPlan.count,
          total_workout_sessions: WorkoutSession.count,
          total_uploads: UserMedia.count,

          # Fitness Intelligence metrics
          fitness_profiles_count:   FitnessProfile.count,
          insights_generated:       (defined?(CoachInsight) ? CoachInsight.count : 0),
          avg_consistency_score:    FitnessProfile.average(:consistency_score)&.round(2),
          avg_adherence_score:      FitnessProfile.average(:adherence_score)&.round(2),
          top_persona:              FitnessProfile.group(:primary_persona).count.max_by { |_, v| v }&.first,
          top_archetype:            FitnessProfile.group(:training_archetype).count.max_by { |_, v| v }&.first,
          top_behavior_pattern:     FitnessProfile.group(:behavior_pattern).count.max_by { |_, v| v }&.first,
          ai_workouts_generated:    AiTrainingDecisionLog.where(status: "success").count,
          ai_validation_failures:   AiTrainingDecisionLog.where(status: "validation_failed").count,
          pct_users_with_insights:  total_users > 0 ? ((defined?(CoachInsight) ? CoachInsight.distinct.count(:user_id) : 0).to_f / total_users * 100).round(1) : 0,

          # Onboarding Analytics
          onboarding_analytics: onboarding_analytics,

          # Activation push (Android MVP)
          push_activation: push_activation_stats,

          # Composite training block usage
          block_usage_metrics: BlockUsageMetricsService.new.call
        }
      rescue ActiveRecord::StatementInvalid => e
        # Tipicamente PG::UndefinedColumn/UndefinedTable quando o schema do banco
        # esta desatualizado (migration pendente em producao). Degradar para 503
        # com mensagem clara em vez de 500 cru para nao derrubar o painel inteiro.
        Rails.logger.error("[AdminController#stats] schema/query failure: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
        render_error(
          "Estatisticas indisponiveis: schema do banco desatualizado (migration pendente)",
          status: :service_unavailable
        )
      end

      def users
        filter  = params[:filter]
        page    = [ params[:page].to_i, 1 ].max
        per     = 25

        # Evitar expor PII na listagem administrativa para reduzir risco em prints e compartilhamento de tela.
        scope = User.all
                    .left_joins(:subscription)
                    .includes(:subscription, :workout_plans, :workout_sessions, :user_events, :user_segments, :fitness_profile)

        scope = apply_filter(scope, filter)
        total = scope.count("users.id")
        users = scope.order("users.created_at DESC")
                     .limit(per)
                     .offset((page - 1) * per)

        render json: {
          users: users.map { |u| user_row(u) },
          total: total,
          page: page,
          per: per
        }
      end

      def user_detail
        user = User.includes(:subscription, :workout_plans, :workout_sessions, :user_events, :user_segments)
                   .find(params[:id])
        render json: full_user_detail(user)
      end

      # POST /api/v1/admin/push_test
      # Sends the standard admin test push to the CURRENT admin's own device
      # tokens. Guarded by require_admin!; self-only (never reads a user_id from
      # params); rate-limited and audited inside AdminPushTestService.
      def push_test
        result = AdminPushTestService.new(current_user).call

        render(
          json: {
            ok: result.ok?,
            error: result.error,
            correlation_id: result.correlation_id,
            devices: Array(result.devices).map do |d|
              {
                masked_token: d.masked_token,
                status: d.status,
                message_id: d.message_id,
                error_code: d.error_code,
                invalidated: d.invalidated
              }
            end
          },
          status: push_test_http_status(result)
        )
      end

      private

      def push_test_http_status(result)
        return :ok if result.ok?

        case result.error
        when "rate_limited" then :too_many_requests
        when "not_configured" then :service_unavailable
        when "not_admin" then :forbidden
        else :unprocessable_entity
        end
      end

      # Activation push panel — aggregate only, never exposes tokens or PII.
      def push_activation_stats
        deliveries = NotificationDelivery.all
        by_status = deliveries.group(:status).count
        prefs = UserNotificationPreferences.all
        event_counts = UserEvent
          .where(event_name: %w[workout_started_from_push workout_completed_from_push])
          .group(:event_name).count
        dislike_reasons = UserEvent.where(event_name: "notification_disliked")
          .group(Arel.sql("metadata->>'reason'")).count

        {
          enabled: PushActivationEligibility.enabled?,
          experiment_enabled: PushActivationEligibility.experiment_enabled?,
          firebase_configured: FirebasePushService.configured?,
          permission: {
            opt_in_reminders: prefs.where(workout_reminders_enabled: true).count,
            push_enabled: prefs.where(push_enabled: true).count,
            permission_granted: prefs.where.not(permission_granted_at: nil).count,
            opted_out: prefs.where.not(notifications_disabled_at: nil).count,
            active_devices: DeviceToken.active.where(platform: "android").count
          },
          funnel: {
            scheduled: deliveries.count,
            sent: deliveries.where.not(sent_at: nil).count,
            opened: deliveries.where.not(opened_at: nil).count,
            converted: deliveries.where.not(converted_at: nil).count,
            workout_started_from_push: event_counts["workout_started_from_push"].to_i,
            workout_completed_from_push: event_counts["workout_completed_from_push"].to_i
          },
          experiment: {
            treatment: prefs.where(activation_push_variant: "treatment").count,
            control: prefs.where(activation_push_variant: "control").count
          },
          preferences: {
            reasons_disabled: prefs.where.not(disabled_reason: nil).group(:disabled_reason).count,
            dislike_reasons: dislike_reasons
          },
          performance: {
            sent: deliveries.where.not(sent_at: nil).count,
            failed: by_status["failed"].to_i,
            skipped: by_status["skipped"].to_i,
            tokens_invalidated: DeviceToken.where.not(invalidated_at: nil).count,
            retries: deliveries.sum(:retry_count)
          },
          # V1 push journey — one row per event (Family A / Make).
          push_journey: push_journey_stats
        }
      end

      # Per-event funnel for the 5 push journey events. Reuses user_events
      # (funnel/attribution) and push_dispatches. Filters: period_days, event_name.
      def push_journey_stats
        since = (params[:period_days].presence&.to_i || 30).days.ago
        events = CommunicationEvents.push_events
        events &= [ params[:event_name] ] if params[:event_name].present?

        ue = UserEvent.where(created_at: since..)
        pd = PushDispatch.where(created_at: since..)
        by_meta = ->(name) { ue.where(event_name: name).group(Arel.sql("metadata->>'event_name'")).count }

        eligible = by_meta.call("push_event_eligible")
        requested = by_meta.call("push_requested_to_make")
        skipped = by_meta.call("push_dispatch_skipped")
        started = by_meta.call("workout_started_from_push")
        completed = by_meta.call("workout_completed_from_push")
        accepted = pd.where(status: PushDispatch::DELIVERED_STATUSES).group(:campaign_key).count
        opened = pd.where.not(opened_at: nil).group(:campaign_key).count

        rows = events.map do |name|
          {
            event_name: name,
            eligible: eligible[name].to_i,
            requested_to_make: requested[name].to_i,
            provider_accepted: accepted[name].to_i,
            opened: opened[name].to_i,
            workouts_started_24h: started[name].to_i,
            workouts_completed_24h: completed[name].to_i,
            skips: skipped[name].to_i
          }
        end

        {
          period_days: (params[:period_days].presence&.to_i || 30),
          opt_outs: UserNotificationPreferences.where.not(notifications_disabled_at: nil).count,
          events: rows
        }
      end

      def require_admin!
        return if current_user&.admin?
        render json: { error: "Unauthorized" }, status: :forbidden
      end

      def apply_filter(scope, filter)
        case filter
        when "trial_active"
          scope.where("users.trial_ends_at > ?", Time.current)
               .where("subscriptions.status IS NULL OR subscriptions.status NOT IN ('active','trialing')")
        when "trial_expired"
          scope.where("users.trial_ends_at <= ?", Time.current)
               .where("subscriptions.status IS NULL OR subscriptions.status NOT IN ('active','trialing')")
        when "premium"
          scope.where(subscriptions: { status: %w[active trialing] })
        when "no_workout"
          scope.left_joins(:workout_plans).where(workout_plans: { id: nil })
        when "plan_no_session"
          scope.joins(:workout_plans)
               .left_joins(:workout_sessions)
               .where(workout_sessions: { id: nil })
               .distinct
        when "1_session"
          scope.joins(:workout_sessions).group("users.id").having("COUNT(workout_sessions.id) = 1")
        when "3plus_sessions"
          scope.joins(:workout_sessions).group("users.id").having("COUNT(workout_sessions.id) >= 3")
        when "active_7d"
          scope.joins(:workout_sessions).where("workout_sessions.completed_at > ?", 7.days.ago).distinct
        when "inactive_7d"
          scope.left_joins(:workout_sessions)
               .where("workout_sessions.id IS NULL OR workout_sessions.completed_at <= ?", 7.days.ago)
               .distinct
        when "engagement_high"
          scope.joins(:workout_sessions).group("users.id").having("COUNT(workout_sessions.id) >= 3")
        when "engagement_medium"
          scope.joins(:workout_sessions).group("users.id").having("COUNT(workout_sessions.id) BETWEEN 1 AND 2")
        when "engagement_low"
          scope.left_joins(:workout_plans, :workout_sessions)
               .where(workout_plans: { id: nil }, workout_sessions: { id: nil })
        when /\Asegment:(.+)\z/
          scope.joins(:user_segments)
               .where(user_segments: { segment_name: Regexp.last_match(1), active: true })
        else
          scope
        end
      end

      def user_row(user)
        sub            = user.subscription
        sessions_count = user.workout_sessions.size
        plans_count    = user.workout_plans.size
        activity       = last_activity_for(user)
        trial_status   = compute_trial_status(user, sub)

        fp = user.fitness_profile
        {
          id: user.id,
          admin_display_id: admin_display_id(user),
          display_name: display_name(user),
          created_at: user.created_at.iso8601,
          trial_status: trial_status,
          trial_days_remaining: user.trial_days_remaining,
          workouts_created: plans_count,
          sessions_completed: sessions_count,
          last_activity_at: activity[:at],
          last_activity_label: activity[:label],
          engagement_level: engagement_score(sessions_count, plans_count, user.workout_sessions),
          active_segments: user.user_segments.select(&:active?).map(&:segment_name).sort,
          primary_persona:          fp&.primary_persona,
          training_archetype:       fp&.training_archetype,
          behavior_pattern:         fp&.behavior_pattern,
          consistency_score:        fp&.consistency_score,
          adherence_score:          fp&.adherence_score,
          risk_score:               fp&.risk_score,
          fitness_profile_last_recalculated_at: fp&.last_recalculated_at
        }
      end

      def full_user_detail(user)
        sub            = user.subscription
        sessions_count = user.workout_sessions.size
        plans_count    = user.workout_plans.size
        activity       = last_activity_for(user)
        trial_status   = compute_trial_status(user, sub)

        {
          id: user.id,
          admin_display_id: admin_display_id(user),
          display_name: display_name(user),
          name: user.name,
          email: user.email,
          created_at: user.created_at.iso8601,
          trial_status: trial_status,
          trial_days_remaining: user.trial_days_remaining,
          trial_ends_at: user.trial_ends_at&.iso8601,
          workouts_created: plans_count,
          sessions_completed: sessions_count,
          last_activity_at: activity[:at],
          last_activity_label: activity[:label],
          engagement_level: engagement_score(sessions_count, plans_count, user.workout_sessions),
          active_segments: user.user_segments.select(&:active?).map(&:segment_name).sort,
          recent_events: user.user_events
                             .sort_by(&:created_at).last(10).reverse
                             .map { |e| { name: e.event_name, created_at: e.created_at.iso8601, make_delivery_status: e.make_delivery_status } }
        }
      end

      def compute_trial_status(user, sub)
        if sub&.status&.in?(%w[active trialing])
          sub.status == "trialing" ? "stripe_trial" : "premium"
        elsif user.trial_active?
          "trial_active"
        elsif user.trial_expired?
          "trial_expired"
        else
          "no_trial"
        end
      end

      ACTIVATION_ONBOARDING_EVENT_NAMES = %w[
        activation_ready_screen_viewed
        activation_preview_viewed
        activation_exercise_details_opened
        activation_start_clicked
        first_exercise_started
        first_exercise_completed
      ].freeze

      ACTIVATION_USER_EVENT_NAMES = %w[activation_workout_created activation_first_workout_completed].freeze

      def recent_activation_events_rows
        onboarding_rows = OnboardingEvent.where(event_name: ACTIVATION_ONBOARDING_EVENT_NAMES)
                                          .includes(:user).order(occurred_at: :desc).limit(20)
        user_event_rows = UserEvent.where(event_name: ACTIVATION_USER_EVENT_NAMES)
                                    .includes(:user).order(occurred_at: :desc).limit(20)

        (onboarding_rows.to_a + user_event_rows.to_a)
          .sort_by { |event| event.occurred_at || event.created_at }
          .reverse
          .first(20)
          .map { |event| activation_event_row(event) }
      end

      def activation_event_row(event)
        user = event.user
        metadata = event.metadata.is_a?(Hash) ? event.metadata : {}
        {
          occurred_at: (event.occurred_at || event.created_at)&.iso8601,
          user_display_name: user ? display_name(user) : nil,
          event_name: event.event_name,
          workout_plan_id: metadata["workout_plan_id"] || metadata.dig("workout", "id"),
          metadata_summary: metadata.slice("workout_plan_id", "workout_session_id", "workout_day_id", "exercise_id")
        }
      end

      def admin_display_id(user)
        "EH-#{user.id.to_s.rjust(6, '0')}"
      end

      def display_name(user)
        return "Usuário #{admin_display_id(user)}" if user.name.blank?
        parts = user.name.strip.split
        return parts.first if parts.size == 1
        "#{parts.first} #{parts.last[0]}."
      end

      def last_activity_for(user)
        last_event   = user.user_events.max_by(&:created_at)
        last_session = user.workout_sessions.max_by(&:completed_at)
        last_time    = [ last_event&.created_at, last_session&.completed_at ].compact.max
        { at: last_time&.iso8601, label: last_time ? relative_time_label(last_time) : "Nunca" }
      end

      def relative_time_label(time)
        diff = Time.current - time
        if    diff < 1.hour   then "Agora"
        elsif diff < 2.hours  then "Há 1 hora"
        elsif diff < 24.hours then "Há #{(diff / 1.hour).round} horas"
        elsif diff < 48.hours then "Ontem"
        elsif diff < 7.days   then "Há #{(diff / 1.day).round} dias"
        else time.strftime("%d/%m/%Y")
        end
      end

      def engagement_score(sessions_count, plans_count, sessions)
        active_days_7d = sessions
                         .select { |s| s.completed_at && s.completed_at > 7.days.ago }
                         .map { |s| s.completed_at.to_date }.uniq.size
        if sessions_count >= 3 || active_days_7d >= 3
          "high"
        elsif plans_count > 0 || sessions_count >= 1 || active_days_7d > 0
          "medium"
        else
          "low"
        end
      end
    end
  end
end
