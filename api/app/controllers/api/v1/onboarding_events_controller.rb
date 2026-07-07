module Api
  module V1
    class OnboardingEventsController < BaseController
      def create
        OnboardingEventTracker.track(
          user: current_user,
          event_name: params[:event_name],
          onboarding_flow: params[:onboarding_flow],
          step_name: params[:step_name],
          metadata: metadata_param,
          occurred_at: occurred_at_param
        )

        head :no_content
      end

      private

      def metadata_param
        params[:metadata].is_a?(ActionController::Parameters) ? params[:metadata].to_unsafe_h : {}
      end

      def occurred_at_param
        Time.zone.parse(params[:occurred_at].to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
