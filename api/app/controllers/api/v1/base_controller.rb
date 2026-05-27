module Api
  module V1
    class BaseController < ApplicationController
      include AiLogging
      include RateLimiter

      before_action :authenticate_user!
      before_action :set_sentry_user_context

      private

      def set_sentry_user_context
        return unless current_user && Sentry.initialized?

        masked_email = begin
          local, domain = current_user.email.to_s.split("@")
          "#{local[0]}***@#{domain}"
        rescue
          "[masked]"
        end

        Sentry.set_user(id: current_user.id, email: masked_email)
      end

      def render_error(message, status: :unprocessable_entity)
        render json: { error: message }, status: status
      end
    end
  end
end
