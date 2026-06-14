module Api
  module V1
    module Auth
      class OmniauthCallbacksController < ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        def google_oauth2
          user = User.from_omniauth(request.env["omniauth.auth"])
          sign_in(user)

          new_user = user.created_at > 5.minutes.ago && user.health_profile.nil?
          redirect_to "#{ENV.fetch('FRONTEND_URL')}#{new_user ? '/onboarding' : '/dashboard'}"
        rescue ActiveRecord::RecordInvalid => e
          Rails.logger.error("OAuth sign-in failed: #{e.message}")
          redirect_to "#{ENV.fetch('FRONTEND_URL')}/login?error=oauth_failed"
        end

        def failure
          redirect_to "#{ENV.fetch('FRONTEND_URL')}/login?error=oauth_failed"
        end
      end
    end
  end
end
