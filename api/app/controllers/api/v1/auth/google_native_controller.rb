module Api
  module V1
    module Auth
      # Native Google Sign-In for the Android app. The app obtains a Google ID
      # token from the native account picker (no browser, no intermediate screen)
      # and posts it here. We verify the token and reuse the same user
      # provisioning as the web OmniAuth flow (User.from_omniauth).
      class GoogleNativeController < ApplicationController
        include AppInstallationReconciliation

        skip_before_action :authenticate_user!, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        CONSENT_REQUIRED_MESSAGE =
          "Para criar sua conta, aceite os Termos de Uso e a Política de Privacidade.".freeze

        def create
          Rails.logger.info(
            "[GoogleNative] received flow=native platform=#{params[:platform]} " \
            "token_present=#{params[:id_token].present?} consent_present=#{consent_present?}"
          )

          claims = ::Auth::GoogleIdTokenVerifier.verify!(params[:id_token], audiences)
          # Never log the full address: the caller is still unauthenticated here.
          Rails.logger.info("[GoogleNative] verified aud=#{claims['aud']} sub=#{claims['sub']} email_domain=#{email_domain(claims['email'])}")

          user = User.from_omniauth(build_auth_hash(claims), consent: consent_params)

          if user.anonymized_at.present?
            Rails.logger.info("[GoogleNative] blocked anonymized user_id=#{user.id}")
            render json: { error: "Conta excluída", error_code: "account_deleted" }, status: :forbidden
            return
          end

          sign_in(user)
          set_auth_indicator_cookie
          Rails.logger.info("[GoogleNative] signed in flow=native platform=#{platform} user_id=#{user.id} new_user=#{new_user?(user)}")
          render json: user_json(user).merge(new_user: new_user?(user)), status: :ok
        rescue ::Auth::GoogleIdTokenVerifier::VerificationError => e
          Rails.logger.warn("[GoogleNative] verification failed: #{e.message}")
          render json: { error: "Token inválido", error_code: "invalid_token" }, status: :unauthorized
        rescue User::BlockedEmailError
          Rails.logger.info("[GoogleNative] blocked email attempted signup")
          render json: { error: "Conta excluída", error_code: "account_deleted" }, status: :forbidden
        rescue User::ConsentRequiredError
          Rails.logger.info("[GoogleNative] blocked signup missing consent flow=native platform=#{platform}")
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
          render json: { error: "Falha no login", error_code: "oauth_failed" }, status: :internal_server_error
        end

        private

        def audiences
          [ ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_ANDROID_CLIENT_ID"] ].compact
        end

        def platform
          params[:platform].presence || "android"
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
