module Api
  module V1
    class NotificationPreferencesController < BaseController
      def show
        render json: preferences_json
      end

      # POST and PATCH share the same upsert semantics.
      def create
        update
      end

      def update
        prefs = current_user.notification_preferences!
        was_reminders_on = prefs.workout_reminders_enabled?
        was_push_on = prefs.push_enabled?

        ActiveRecord::Base.transaction do
          apply_preferred_time!
          prefs.update!(preference_params)
          apply_side_effects!(prefs, was_reminders_on:, was_push_on:)
        end

        render json: preferences_json
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      private

      def preference_params
        params.permit(:push_enabled, :workout_reminders_enabled, :workout_ready_enabled, :timezone)
      end

      # preferred_workout_period / preferred_workout_time live on the health
      # profile (source of truth). Updating them here counts as a manual change.
      def apply_preferred_time!
        return unless params.key?(:preferred_workout_period) || params.key?(:preferred_workout_time)

        profile = current_user.health_profile || current_user.build_health_profile
        profile.preferred_workout_period = params[:preferred_workout_period] if params.key?(:preferred_workout_period)
        profile.preferred_workout_time = params[:preferred_workout_time] if params.key?(:preferred_workout_time)
        profile.workout_time_source = "manually_changed"
        profile.preferred_workout_time_updated_at = Time.current
        # Skip full validation: the profile may be incomplete at this point and we
        # only touch notification-related columns.
        profile.save!(validate: false)

        # Reschedule: drop any pending deliveries; the next sweep re-schedules with
        # the new local time.
        NotificationDelivery.cancel_pending_for(current_user, reason: "time_changed")
        track("notification_time_changed", period: profile.preferred_workout_period)

        # Persist timezone at the user level if provided.
        current_user.update!(time_zone: params[:timezone]) if params[:timezone].present?
      end

      def apply_side_effects!(prefs, was_reminders_on:, was_push_on:)
        if !was_push_on && prefs.push_enabled?
          # First time push is turned on (post native grant) — stamp the funnel.
          prefs.update!(
            permission_requested_at: prefs.permission_requested_at || Time.current,
            permission_granted_at: prefs.permission_granted_at || Time.current,
            prepermission_answered_at: prefs.prepermission_answered_at || Time.current
          )
        end

        if was_reminders_on && !prefs.workout_reminders_enabled?
          NotificationDelivery.cancel_pending_for(current_user, reason: "user_settings")
          track("notification_type_disabled", reason: "user_settings")
        end

        if was_push_on && !prefs.push_enabled?
          # Turning off system push disables every device but keeps per-type
          # preferences and history for future re-activation.
          current_user.device_tokens.active.find_each { |d| d.invalidate!("user_disabled_push") }
          NotificationDelivery.cancel_pending_for(current_user, reason: "push_disabled")
          prefs.update!(notifications_disabled_at: Time.current, disabled_reason: "user_settings")
        elsif prefs.push_enabled?
          # Explicit opt-in: always clear any prior global opt-out state so the
          # consent flow is the single source that (re)enables push. Idempotent —
          # also repairs an inconsistent row (disabled_reason set, disabled_at nil).
          prefs.update!(notifications_disabled_at: nil, disabled_reason: nil)
        end
      end

      def preferences_json
        prefs = current_user.notification_preferences!
        profile = current_user.health_profile
        {
          push_enabled: prefs.push_enabled,
          workout_reminders_enabled: prefs.workout_reminders_enabled,
          workout_ready_enabled: prefs.workout_ready_enabled,
          preferred_workout_period: profile&.preferred_workout_period,
          preferred_workout_time: profile&.preferred_workout_time&.strftime("%H:%M"),
          timezone: current_user.time_zone || prefs.timezone,
          notifications_disabled_at: prefs.notifications_disabled_at,
          has_active_device: current_user.device_tokens.active.exists?
        }
      end

      def track(event_name, extra = {})
        UserEventService.track(
          user: current_user,
          event_name: event_name,
          source: "activation_push",
          suppress_make_delivery: true,
          metadata: { platform: "android" }.merge(extra)
        )
      end
    end
  end
end
