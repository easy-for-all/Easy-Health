module Api
  module V1
    module Auth
      # Native Google Sign-In for the Android app. The app obtains a Google ID
      # token from the native account picker (no browser, no intermediate screen)
      # and posts it here. We verify the token and reuse the same user
      # provisioning as the web OmniAuth flow (User.from_omniauth).
      class GoogleNativeController < ApplicationController
        skip_before_action :authenticate_user!, raise: false
        skip_before_action :verify_authenticity_token, raise: false

        def create
          Rails.logger.info("[GoogleNative] received platform=#{params[:platform]} token_present=#{params[:id_token].present?}")

          claims = ::Auth::GoogleIdTokenVerifier.verify!(params[:id_token], audiences)
          Rails.logger.info("[GoogleNative] verified aud=#{claims['aud']} sub=#{claims['sub']} email=#{claims['email']}")

          user = User.from_omniauth(build_auth_hash(claims))

          if user.anonymized_at.present?
            Rails.logger.info("[GoogleNative] blocked anonymized user_id=#{user.id}")
            render json: { error: "Conta excluída", error_code: "account_deleted" }, status: :forbidden
            return
          end

          sign_in(user)
          set_auth_indicator_cookie
          Rails.logger.info("[GoogleNative] signed in user_id=#{user.id} new_user=#{new_user?(user)}")
          render json: user_json(user).merge(new_user: new_user?(user)), status: :ok
        rescue ::Auth::GoogleIdTokenVerifier::VerificationError => e
          Rails.logger.warn("[GoogleNative] verification failed: #{e.message}")
          render json: { error: "Token inválido", error_code: "invalid_token" }, status: :unauthorized
        rescue User::BlockedEmailError
          Rails.logger.info("[GoogleNative] blocked email attempted signup")
          render json: { error: "Conta excluída", error_code: "account_deleted" }, status: :forbidden
        rescue => e
          Rails.logger.error("[GoogleNative] error #{e.class}: #{e.message}")
          render json: { error: "Falha no login", error_code: "oauth_failed" }, status: :internal_server_error
        end

        private

        def audiences
          [ ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_ANDROID_CLIENT_ID"] ].compact
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
