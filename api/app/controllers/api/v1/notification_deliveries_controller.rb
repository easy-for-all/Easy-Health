module Api
  module V1
    class NotificationDeliveriesController < BaseController
      before_action :set_delivery

      DISLIKE_REASONS = %w[bad_time too_many trained_elsewhere not_this_type].freeze

      # Called by the client when the user taps the push (deep-link open).
      def opened
        @delivery.update!(
          status: @delivery.terminal? ? @delivery.status : "opened",
          opened_at: @delivery.opened_at || Time.current,
          clicked_at: Time.current
        )
        track("push_opened")
        track("push_deep_link_opened")
        head :ok
      end

      # "Não gostei deste lembrete" feedback. No free text in this MVP.
      def dislike
        reason = params[:reason].to_s
        return render json: { error: "invalid_reason" }, status: :unprocessable_entity unless DISLIKE_REASONS.include?(reason)

        apply_dislike(reason)
        track("notification_disliked", reason: reason)
        render json: { ok: true }
      end

      private

      def set_delivery
        @delivery = current_user.notification_deliveries.find(params[:id])
      end

      def apply_dislike(reason)
        prefs = current_user.notification_preferences!
        case reason
        when "too_many"
          # Stop the pending recovery and shrink this flow's budget.
          NotificationDelivery.cancel_pending_for(current_user, reason: "dislike_too_many", types: "first_workout_recovery")
          prefs.update!(max_pushes_per_week: 1, activation_notifications_completed_at: Time.current)
        when "trained_elsewhere"
          # End the activation flow WITHOUT marking any workout as completed.
          NotificationDelivery.cancel_pending_for(current_user, reason: "dislike_trained_elsewhere")
          prefs.update!(activation_notifications_completed_at: Time.current)
        when "not_this_type"
          NotificationDelivery.cancel_pending_for(current_user, reason: "dislike_not_this_type")
          prefs.update!(
            workout_reminders_enabled: false,
            notifications_disabled_at: Time.current,
            disabled_reason: "dislike_not_this_type"
          )
          track("notification_type_disabled", reason: "dislike_not_this_type")
        when "bad_time"
          # The client opens the time editor; scheduling changes are handled by the
          # preferences endpoint. Nothing to disable here.
        end
      end

      def track(event_name, extra = {})
        UserEventService.track(
          user: current_user,
          event_name: event_name,
          source: "activation_push",
          suppress_make_delivery: true,
          metadata: {
            notification_type: @delivery.notification_type,
            delivery_id: @delivery.id,
            platform: "android"
          }.merge(extra)
        )
      end
    end
  end
end
