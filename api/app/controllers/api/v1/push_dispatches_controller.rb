module Api
  module V1
    # Open tracking for Make-orchestrated pushes (Family A). The app posts here
    # when the user taps a push whose data carries a dispatch_id. Stamps opened_at
    # (basis for 24h attribution) and records the funnel open events. Scoped to
    # the current user — a dispatch is never exposed across accounts.
    class PushDispatchesController < BaseController
      def opened
        dispatch = PushDispatch.find_by(id: params[:id], user_id: current_user.id)
        return head :not_found unless dispatch

        dispatch.mark_opened!
        track("push_opened", dispatch)
        track("push_deep_link_opened", dispatch)
        head :ok
      end

      private

      def track(event_name, dispatch)
        UserEventService.track(
          user: current_user,
          event_name: event_name,
          source: "make_push",
          suppress_make_delivery: true,
          metadata: {
            dispatch_id: dispatch.id,
            notification_type: dispatch.notification_type,
            campaign_key: dispatch.campaign_key,
            platform: "android"
          }
        )
      end
    end
  end
end
