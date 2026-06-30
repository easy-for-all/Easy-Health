module Api
  module V1
    module Auth
      class MobileCallbacksController < ApplicationController
        skip_before_action :authenticate_user!, raise: false

        def exchange
          token = params[:token].to_s.strip
          if token.blank?
            render json: { error: "Token ausente" }, status: :bad_request
            return
          end

          cached = Rails.cache.read("mobile_auth:#{token}")
          if cached.nil?
            render json: { error: "Token inválido ou expirado" }, status: :unauthorized
            return
          end

          Rails.cache.delete("mobile_auth:#{token}")
          user = User.find_by(id: cached[:user_id])
          if user.nil?
            render json: { error: "Usuário não encontrado" }, status: :not_found
            return
          end

          sign_in(user)
          cookies[:_eh_auth] = { value: "1", domain: ".easyhealth.art", path: "/", secure: Rails.env.production?, httponly: false, same_site: :lax }
          render json: user_json(user).merge(new_user: cached[:new_user]), status: :ok
        end
      end
    end
  end
end
