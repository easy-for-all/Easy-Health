module Api
  module V1
    module Auth
      class OmniauthCallbacksController < ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        FRONTEND = ENV.fetch("FRONTEND_URL", "https://easyhealth.art").freeze

        def google_oauth2
          Rails.logger.info("[GoogleOAuth] started uid=#{request.env.dig('omniauth.auth', 'uid')}")
          user = User.from_omniauth(request.env["omniauth.auth"])
          sign_in(user)
          new_user = user.previously_new_record? || (user.created_at > 5.minutes.ago && user.health_profile.nil?)
          Rails.logger.info("[GoogleOAuthCallback] email=#{user.email} new_user=#{new_user}")
          redirect_to "#{FRONTEND}#{new_user ? '/onboarding' : '/dashboard'}", allow_other_host: true
        rescue => e
          Rails.logger.error("[GoogleOAuthError] #{e.class}: #{e.message}")
          redirect_to "#{FRONTEND}/login?error=oauth_failed", allow_other_host: true
        end

        def failure
          Rails.logger.error("[GoogleOAuthFailure] message=#{params[:message]}")
          redirect_to "#{FRONTEND}/login?error=oauth_failed", allow_other_host: true
        end
      end
    end
  end
end
