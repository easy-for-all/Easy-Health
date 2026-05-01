module Api
  module V1
    module Auth
      class RegistrationsController < ApplicationController
        def create
          user = User.new(registration_params)

          if user.save
            sign_in(user)
            render json: {
              id: user.id,
              name: user.name,
              email: user.email,
              created_at: user.created_at
            }, status: :created
          else
            render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        private

        def registration_params
          params.permit(:name, :email, :password, :password_confirmation)
        end
      end
    end
  end
end
