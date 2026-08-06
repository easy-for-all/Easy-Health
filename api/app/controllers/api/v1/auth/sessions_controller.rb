module Api
  module V1
    module Auth
      class SessionsController < ApplicationController
        include AppInstallationReconciliation
        include EmailAuthTelemetry

        before_action :authenticate_user!, only: [:show]

        def show
          render json: user_json(current_user)
        end

        def create
          # First line of the action on purpose: this is the event that means
          # "the login request really entered the controller", which is exactly
          # what the client cannot know and the funnel could not see.
          emit_email_auth_started("login")

          user = User.find_by(email: params[:email]&.downcase)

          if user&.valid_password?(params[:password])
            sign_in(user)
            set_auth_indicator_cookie
            emit_email_auth_succeeded("login", user: user)
            render json: user_json(user), status: :ok
          else
            # One category for both branches, deliberately: telling "no such
            # account" apart from "wrong password" in telemetry is the same
            # account-enumeration leak the response itself refuses to make.
            emit_email_auth_failed("login", "invalid_credentials")
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
      end
    end
  end
end
