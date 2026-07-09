module Api
  module V1
    module Auth
      class OmniauthCallbacksController < ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        FRONTEND = ENV.fetch("FRONTEND_URL", "https://easyhealth.art").freeze

        def google_oauth2
          handle_google_callback(mobile: false)
        end

        # Same Google strategy, mounted on a separate path (see devise.rb) so the
        # mobile-vs-web decision is derived from `auth.provider` instead of a
        # `mobile=1` query param that depended on the Rack session surviving the
        # redirect round-trip through Google — which the in-app browser (Custom
        # Tab) doesn't reliably preserve.
        def google_oauth2_mobile
          handle_google_callback(mobile: true)
        end

        def failure
          Rails.logger.error("[GoogleOAuthFailure] message=#{params[:message]}")
          redirect_to "#{FRONTEND}/login?error=oauth_failed", allow_other_host: true
        end

        private

        def handle_google_callback(mobile:)
          Rails.logger.info("[GoogleOAuth] started uid=#{request.env.dig('omniauth.auth', 'uid')} mobile=#{mobile}")
          user = User.from_omniauth(request.env["omniauth.auth"])

          if user.anonymized_at.present?
            Rails.logger.info("[GoogleOAuthCallback] blocked login for anonymized user_id=#{user.id}")
            redirect_to "#{FRONTEND}/login?error=account_deleted", allow_other_host: true
            return
          end

          sign_in(user)
          set_auth_indicator_cookie
          new_user = user.previously_new_record? || (user.created_at > 5.minutes.ago && user.health_profile.nil?)
          Rails.logger.info("[GoogleOAuthCallback] email=#{user.email} new_user=#{new_user}")

          if mobile
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
      end
    end
  end
end
