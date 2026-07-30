module Api
  module V1
    module Auth
      # Native Google Sign-In for the Android app. The app obtains a Google ID
      # token from the native account picker (no browser, no intermediate screen)
      # and posts it here. We verify the token and reuse the same user
      # provisioning as the web OmniAuth flow (User.from_omniauth).
      class GoogleNativeController < ApplicationController
        include AppInstallationReconciliation
        include SignupSourceContext

        skip_before_action :authenticate_user!, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        CONSENT_REQUIRED_MESSAGE =
          "Para criar sua conta, aceite os Termos de Uso e a Política de Privacidade.".freeze

        def create
          Observability::Context.auth_flow = "native"
          Observability::Events.google_auth_started(
            flow: "native", intent: auth_intent, terms_accepted: params[:terms_accepted]
          )
          Observability::Events.android_registration_started(source: "google_native") if auth_intent == "sign_up"

          claims = ::Auth::GoogleIdTokenVerifier.verify!(params[:id_token], audiences)
          # Never log the full address: the caller is still unauthenticated here.
          Rails.logger.info("[GoogleNative] verified aud=#{claims['aud']} sub=#{claims['sub']} email_domain=#{email_domain(claims['email'])}")

          user = User.from_omniauth(
            build_auth_hash(claims),
            consent: consent_params,
            signup_source: native_signup_source
          )

          if user.anonymized_at.present?
            auth_failed("account_deleted")
            render json: { error: "Conta excluída", error_code: "account_deleted" }, status: :forbidden
            return
          end

          sign_in(user)
          set_auth_indicator_cookie
          fresh_account = new_user?(user)
          Observability::Context.user_id = user.id
          installation_link_result = reconcile_app_installation
          Observability::Events.google_auth_succeeded(
            flow: "native", user: user, new_user: fresh_account, intent: auth_intent
          )
          if fresh_account
            Observability::Events.android_registration_succeeded(
              user: user,
              new_user: true,
              installation_linked: installation_link_result&.success == true
            )
          end
          render json: user_json(user).merge(new_user: fresh_account), status: :ok
        rescue ::Auth::GoogleIdTokenVerifier::VerificationError => e
          # Message text stays out of the event: an invalid audience and an
          # expired token are different failures and must be told apart by code,
          # not by string matching. Sentry keeps the detail.
          auth_failed(verification_error_code(e))
          render json: { error: "Token inválido", error_code: "invalid_token" }, status: :unauthorized
        rescue User::BlockedEmailError
          auth_failed("account_deleted")
          render json: { error: "Conta excluída", error_code: "account_deleted" }, status: :forbidden
        rescue User::ConsentRequiredError
          auth_failed("consent_required")
          # `action` tells the client this Google account simply does not exist
          # yet and the way forward is the sign-up screen — not a retry here.
          render json: {
            error: "consent_required",
            error_code: "consent_required",
            message: CONSENT_REQUIRED_MESSAGE,
            action: "sign_up"
          }, status: :unprocessable_entity
        rescue => e
          Rails.logger.error("[GoogleNative] error #{e.class}: #{e.message}")
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          auth_failed("internal_error")
          render json: { error: "Falha no login", error_code: "oauth_failed" }, status: :internal_server_error
        end

        private

        def auth_failed(error_code)
          Observability::Events.google_auth_failed(
            flow: "native",
            error_code: error_code,
            intent: auth_intent,
            terms_accepted: params[:terms_accepted]
          )
          Observability::Events.android_registration_failed(error_code: error_code) if auth_intent == "sign_up"
        end

        # The client tells us what it was trying to do. Combined with
        # terms_accepted this is what makes consent_required classifiable:
        # expected on a login against a non-existent account, a bug on a sign-up
        # that already collected consent.
        def auth_intent
          return "sign_up" if ActiveModel::Type::Boolean.new.cast(params[:terms_accepted])

          params[:intent].presence_in(Observability::Events::AUTH_INTENTS) || "login"
        end

        def verification_error_code(error)
          error.message.to_s.downcase.include?("audience") ? "invalid_audience" : "invalid_token"
        end

        def audiences
          [ ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_ANDROID_CLIENT_ID"] ].compact
        end

        def platform
          params[:platform].presence || "android"
        end

        # Header first (observed by the server), params[:platform] as the
        # client-declared fallback. Deliberately does NOT fall back to "android"
        # the way `platform` above does for consent_source: fabricating "android"
        # would produce exactly the invented data signup_source exists to
        # eliminate. An unattributable signup is worth more as "unknown".
        def native_signup_source
          header = Observability::Headers.platform(request.headers)
          return header if header.present? && header != "unknown"

          signup_source_from_value(params[:platform])
        end

        def consent_present?
          User.required_consent_given?(consent_params)
        end

        def email_domain(email)
          email.to_s.split("@").last
        end

        def consent_params
          {
            terms_accepted: params[:terms_accepted],
            privacy_accepted: params[:privacy_accepted],
            marketing_consent: params[:marketing_consent],
            source: platform
          }
        end

        def build_auth_hash(claims)
          OmniAuth::AuthHash.new(
            provider: "google_oauth2",
            uid: claims["sub"],
            info: {
              email: claims["email"],
              name: claims["name"],
              image: claims["picture"]
            }
          )
        end

        def new_user?(user)
          user.created_at > 5.minutes.ago && user.health_profile.nil?
        end
      end
    end
  end
end
