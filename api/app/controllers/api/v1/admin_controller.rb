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
        users_completed_workouts = User.joins(:workout_sessions).distinct.count
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

        # Retention D1/D7/D30 — base: users registered before the cutoff
        d1_base    = User.where("created_at <= ?", 1.day.ago).count
        d7_base    = User.where("created_at <= ?", 7.days.ago).count
        d30_base   = User.where("created_at <= ?", 30.days.ago).count

        d1_retained = WorkoutSession
          .joins("INNER JOIN users ON users.id = workout_sessions.user_id")
          .where("DATE(workout_sessions.completed_at) = DATE(users.created_at + INTERVAL '1 day')")
          .distinct.count(:user_id)

        d7_retained = WorkoutSession
          .joins("INNER JOIN users ON users.id = workout_sessions.user_id")
          .where("DATE(workout_sessions.completed_at) BETWEEN DATE(users.created_at + INTERVAL '7 days') AND DATE(users.created_at + INTERVAL '8 days')")
          .distinct.count(:user_id)

        d30_retained = WorkoutSession
          .joins("INNER JOIN users ON users.id = workout_sessions.user_id")
          .where("DATE(workout_sessions.completed_at) BETWEEN DATE(users.created_at + INTERVAL '30 days') AND DATE(users.created_at + INTERVAL '31 days')")
          .distinct.count(:user_id)

        # Conversion funnels
        users_subscribed = User.joins(:subscription)
                               .where("subscriptions.status IN ('active','trialing')")
                               .count

        conversion_trial_to_subscription    = total_users > 0 ? (users_subscribed.to_f / total_users * 100).round(1) : 0
        conversion_signup_to_workout_created = total_users > 0 ? (users_created_workouts.to_f / total_users * 100).round(1) : 0
        conversion_plan_to_session          = users_created_workouts > 0 ? (users_completed_workouts.to_f / users_created_workouts * 100).round(1) : 0
        conversion_session_to_subscription  = users_completed_workouts > 0 ? (users_subscribed.to_f / users_completed_workouts * 100).round(1) : 0

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

          # Retention
          retention_d1: d1_base > 0 ? (d1_retained.to_f / d1_base * 100).round(1) : 0,
          retention_d7: d7_base > 0 ? (d7_retained.to_f / d7_base * 100).round(1) : 0,
          retention_d30: d30_base > 0 ? (d30_retained.to_f / d30_base * 100).round(1) : 0,

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

          # Composite training block usage
          block_usage_metrics: BlockUsageMetricsService.new.call
        }
      end

      def users
        filter  = params[:filter]
        page    = [params[:page].to_i, 1].max
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

      private

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
        last_time    = [last_event&.created_at, last_session&.completed_at].compact.max
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
