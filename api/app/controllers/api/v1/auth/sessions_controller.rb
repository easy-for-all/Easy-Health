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
            render json: with_mobile_session(user_json(user), user), status: :ok
          else
            # One category for both branches, deliberately: telling "no such
            # account" apart from "wrong password" in telemetry is the same
            # account-enumeration leak the response itself refuses to make.
            emit_email_auth_failed("login", "invalid_credentials")
            render json: { error: "Invalid email or password" }, status: :unauthorized
          end
        end

        def destroy
          # Um logout que só derruba o cookie deixaria o token do app nativo
          # valendo por 90 dias no aparelho. Revoga o desta requisição, e todos
          # os demais do usuário — "sair" tem que significar sair.
          if user_signed_in?
            MobileSession.revoke_all_for!(current_user, reason: "user_signout")
          else
            current_mobile_session&.revoke!(reason: "user_signout")
          end

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
