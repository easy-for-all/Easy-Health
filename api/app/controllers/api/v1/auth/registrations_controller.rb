module Api
  module V1
    module Auth
      class RegistrationsController < ApplicationController
        before_action :authenticate_user!, only: [:destroy]

        def create
          user = User.new(registration_params)

          if user.save
            sign_in(user)
            user.reload
            render json: user_json(user), status: :created
          else
            render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          AccountDeletionService.new(current_user).call

          sign_out(current_user)
          reset_session
          request.session_options[:drop] = true
          cookies.delete("_easy_health_session", path: "/", same_site: :lax)

          render json: { message: "Account deleted successfully" }, status: :ok
        rescue => e
          render json: { error: "Failed to delete account: #{e.message}" }, status: :unprocessable_entity
        end

        private

        def registration_params
          params.permit(:name, :email, :password, :password_confirmation, :marketing_consent)
        end
      end
    end
  end
end
