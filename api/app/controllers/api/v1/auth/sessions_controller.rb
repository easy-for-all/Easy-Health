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

          render json: { message: "Signed out successfully" }
        end

        private

        def user_json(user)
          avatar_url = blob_path(user.avatar)
          {
            id: user.id,
            name: user.name,
            email: user.email,
            admin: user.admin?,
            created_at: user.created_at,
            avatar_url: avatar_url,
            billing_status: user.billing_status
          }
        end
      end
    end
  end
end
