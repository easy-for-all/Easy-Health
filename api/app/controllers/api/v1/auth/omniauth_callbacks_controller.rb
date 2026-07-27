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
          Observability::Events.google_auth_failed(flow: "web", error_code: "provider_error")
          redirect_to "#{FRONTEND}/login?error=oauth_failed", allow_other_host: true
        end

        private

        # Consent flags travel as query params on the /auth/google/web request
        # phase and are handed back to us on the callback phase via
        # `omniauth.params`. Only consulted when creating a brand-new account.
        def oauth_consent_params
          oauth_params = request.env["omniauth.params"] || {}
          {
            terms_accepted: oauth_params["terms_accepted"],
            privacy_accepted: oauth_params["privacy_accepted"],
            marketing_consent: oauth_params["marketing_consent"],
            source: "web"
          }
        end

        def handle_google_callback(mobile:)
          consent = oauth_consent_params
          @auth_flow = mobile ? "web_mobile" : "web"
          @consent_given = User.required_consent_given?(consent)
          Observability::Context.auth_flow = @auth_flow

          Observability::Events.google_auth_started(
            flow: @auth_flow, intent: auth_intent, terms_accepted: @consent_given
          )

          user = User.from_omniauth(request.env["omniauth.auth"], consent: consent)

          if user.anonymized_at.present?
            oauth_failed("account_deleted")
            redirect_to "#{FRONTEND}/login?error=account_deleted", allow_other_host: true
            return
          end

          new_user = user.previously_new_record? || (user.created_at > 5.minutes.ago && user.health_profile.nil?)
          Observability::Context.user_id = user.id
          Observability::Events.google_auth_succeeded(
            flow: @auth_flow, user: user, new_user: new_user, intent: auth_intent
          )

          if mobile
            code = MobileAuthCode.issue_for!(user: user, platform: "android")
            Rails.logger.info("[GoogleOAuthCallback] mobile flow, redirecting with one-time code")
            redirect_to "#{FRONTEND}/mobile-auth/callback?code=#{code}&platform=android", allow_other_host: true
          else
            sign_in(user)
            set_auth_indicator_cookie
            redirect_to "#{FRONTEND}#{new_user ? '/onboarding' : '/dashboard'}", allow_other_host: true
          end
        rescue User::BlockedEmailError
          oauth_failed("account_deleted")
          redirect_to "#{FRONTEND}/login?error=account_deleted", allow_other_host: true
        rescue User::ConsentRequiredError
          oauth_failed("consent_required")
          # `provider` only opens the sign-up screen in the Google context; the
          # consent itself was never collected, so nothing is pre-accepted.
          redirect_to "#{FRONTEND}/sign-up?error=consent_required&provider=google", allow_other_host: true
        rescue => e
          Rails.logger.error("[GoogleOAuthError] #{e.class}: #{e.message}")
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          oauth_failed("internal_error")
          redirect_to "#{FRONTEND}/login?error=oauth_failed", allow_other_host: true
        end

        def oauth_failed(error_code)
          Observability::Events.google_auth_failed(
            flow: @auth_flow || "web",
            error_code: error_code,
            intent: auth_intent,
            terms_accepted: @consent_given
          )
        end

        # On the web flow consent is only ever supplied by the sign-up screen,
        # so its presence is the intent. A consent_required raised while
        # @consent_given is true is the anomaly the check looks for.
        def auth_intent
          @consent_given ? "sign_up" : "login"
        end
      end
    end
  end
end
