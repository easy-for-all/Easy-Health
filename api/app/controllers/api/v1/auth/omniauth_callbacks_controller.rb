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

          if user.anonymized_at.present?
            Rails.logger.info("[GoogleOAuthCallback] blocked login for anonymized user_id=#{user.id}")
            redirect_to "#{FRONTEND}/login?error=account_deleted", allow_other_host: true
            return
          end

          sign_in(user)
          cookies[:_eh_auth] = { value: "1", domain: ".easyhealth.art", path: "/", secure: true, httponly: false, same_site: :lax }
          new_user = user.previously_new_record? || (user.created_at > 5.minutes.ago && user.health_profile.nil?)
          Rails.logger.info("[GoogleOAuthCallback] email=#{user.email} new_user=#{new_user}")

          if request.env.dig("omniauth.params", "mobile") == "1"
            token = SecureRandom.urlsafe_base64(32)
            Rails.cache.write("mobile_auth:#{token}", { user_id: user.id, new_user: new_user }, expires_in: 5.minutes)
            Rails.logger.info("[GoogleOAuthCallback] mobile flow, redirecting with token")
            redirect_to "easyhealth://auth-callback?token=#{token}", allow_other_host: true
          else
            redirect_to "#{FRONTEND}#{new_user ? '/onboarding' : '/dashboard'}", allow_other_host: true
          end
        rescue User::BlockedEmailError
          Rails.logger.info("[GoogleOAuthCallback] blocked email attempted signup")
          redirect_to "#{FRONTEND}/login?error=account_deleted", allow_other_host: true
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
