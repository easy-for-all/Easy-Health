module Api
  module V1
    module Auth
      class SessionsController < ApplicationController
        before_action :authenticate_user!, only: [:show]

        def show
          render json: user_json(current_user)
        end

        def create
          user = User.find_by(email: params[:email]&.downcase)

          if user&.valid_password?(params[:password])
            sign_in(user)
            set_auth_indicator_cookie
            render json: user_json(user), status: :ok
          else
            render json: { error: "Invalid email or password" }, status: :unauthorized
          end
        end

        def destroy
          sign_out(current_user) if user_signed_in?
          reset_session
          request.session_options[:drop] = true
          cookies.delete("_easy_health_session", path: "/", same_site: :lax)
          delete_auth_indicator_cookie

          render json: { message: "Signed out successfully" }
        end

        private

        def set_auth_indicator_cookie
          cookies[:_eh_auth] = {
            value: "1",
            domain: ".easyhealth.art",
            path: "/",
            secure: Rails.env.production?,
            httponly: false,
            same_site: :lax
          }
        end

        def delete_auth_indicator_cookie
          cookies.delete(:_eh_auth, domain: ".easyhealth.art", path: "/")
        end

        def user_json(user)
          avatar_url = blob_path(user.avatar)
          {
            id: user.id,
            name: user.name,
            email: user.email,
            admin: user.admin?,
            created_at: user.created_at,
            avatar_url: avatar_url,
            billing_status: user.billing_status,
            account_type: user.account_type,
            profile_visibility: user.profile_visibility,
            community_enabled: user.community_enabled,
            referral_code: user.referral_code
          }
        end
      end
    end
  end
end
