module Api
  module V1
    module Auth
      class MobileCallbacksController < ApplicationController
        skip_before_action :authenticate_user!, raise: false

        def exchange
          auth_code = MobileAuthCode.redeem!(code: params[:code], platform: params[:platform])
          user = auth_code.user

          if user.anonymized_at.present?
            render json: { error: "Conta excluída" }, status: :forbidden
            return
          end

          sign_in(user)
          set_auth_indicator_cookie
          render json: user_json(user).merge(new_user: new_user?(user)), status: :ok
        rescue MobileAuthCode::InvalidPlatformError
          render json: { error: "Plataforma inválida" }, status: :unprocessable_entity
        rescue MobileAuthCode::InvalidCodeError
          render json: { error: "Código inválido ou expirado" }, status: :unauthorized
        rescue MobileAuthCode::ExpiredCodeError
          render json: { error: "Código expirado" }, status: :unauthorized
        rescue MobileAuthCode::UsedCodeError
          render json: { error: "Código já utilizado" }, status: :unauthorized
        end

        private

        def new_user?(user)
          user.created_at > 5.minutes.ago && user.health_profile.nil?
        end
      end
    end
  end
end
