module Api
  module V1
    module Auth
      class RegistrationsController < ApplicationController
        include AppInstallationReconciliation
        include SignupSourceContext
        include EmailAuthTelemetry

        before_action :authenticate_user!, only: [:destroy]

        def create
          # Emitted before any gate: "the sign-up request reached the API" is a
          # fact about the request, not about whether it was accepted.
          emit_email_auth_started("sign_up")

          unless User.required_consent_given?(consent_params)
            emit_email_auth_failed("sign_up", "validation_error")
            render json: { error: "Aceite os termos para continuar", error_code: "consent_required" }, status: :unprocessable_entity
            return
          end

          user = User.new(
            registration_params
              .merge(User.consent_attributes(consent_params))
              .merge(signup_source: signup_source_from_request)
          )

          if user.save
            sign_in(user)
            set_auth_indicator_cookie
            user.reload
            emit_email_auth_succeeded("sign_up", user: user)
            render json: with_mobile_session(user_json(user), user), status: :created
          else
            # The messages go to the client and to the logs; the event carries
            # only the category, never a field name or a value the user typed.
            emit_email_auth_failed("sign_up", "validation_error")
            render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
          end
        end

        def destroy
          AccountDeletionService.new(current_user).call

          sign_out(current_user)
          reset_session
          request.session_options[:drop] = true
          cookies.delete("_easy_health_session", path: "/", same_site: :lax)
          delete_auth_indicator_cookie

          render json: { message: "Account deleted successfully" }, status: :ok
        rescue => e
          render json: { error: "Failed to delete account: #{e.message}" }, status: :unprocessable_entity
        end

        private

        def registration_params
          params.permit(:name, :email, :password, :password_confirmation)
        end

        def consent_params
          {
            terms_accepted: params[:terms_accepted],
            privacy_accepted: params[:privacy_accepted],
            marketing_consent: params[:marketing_consent],
            source: "web"
          }
        end
      end
    end
  end
end
