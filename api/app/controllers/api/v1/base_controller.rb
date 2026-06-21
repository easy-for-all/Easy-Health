module Api
  module V1
    class BaseController < ApplicationController
      include AiLogging
      include RateLimiter
      include RequiresActiveAccess

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

      def require_personal_trainer!
        return if current_user.personal_trainer?
        render_error("Personal trainer account required", status: :forbidden)
      end

      def serialize_public_profile(user)
        pp = user.public_profile
        workout_count = user.profile_visibility != "private" && pp&.show_workout_count ? user.workout_sessions.count : nil
        {
          id: user.id,
          display_name: pp&.display_name.presence || user.name,
          avatar_url: pp&.avatar_visible && user.avatar.attached? ? blob_path(user.avatar) : nil,
          public_bio: pp&.public_bio,
          profile_visibility: user.profile_visibility,
          account_type: user.account_type,
          show_workout_count: pp&.show_workout_count,
          show_streak: pp&.show_streak,
          workout_count: workout_count
        }
      end
    end
  end
end
