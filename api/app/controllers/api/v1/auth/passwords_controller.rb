require "cgi"

module Api
  module V1
    module Auth
      class PasswordsController < ApplicationController
        GENERIC_MESSAGE = "Se este e-mail estiver cadastrado, enviaremos um link de recuperação."

        # POST /api/v1/auth/password/forgot
        def forgot
          email = params[:email]&.downcase&.strip
          user  = User.find_by(email: email)

          # Always return 200 — never reveal whether e-mail exists
          if user
            token  = SecureRandom.urlsafe_base64(32)
            digest = Digest::SHA256.hexdigest(token)

            user.update_columns(
              reset_password_token_digest: digest,
              reset_password_sent_at:      Time.current
            )

            reset_link = build_reset_link(token, email)
            ResendEmailService.send_password_reset(to: email, reset_link: reset_link)
          end

          render json: { message: GENERIC_MESSAGE }, status: :ok
        end

        # POST /api/v1/auth/password/reset
        def reset
          email    = params[:email]&.downcase&.strip
          token    = params[:token]
          password = params[:password]
          confirmation = params[:password_confirmation]

          user = User.find_by(email: email)

          return render_token_error unless valid_token?(user, token)

          unless user.update(password: password, password_confirmation: confirmation)
            return render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
          end

          # Invalidate token after successful reset
          user.update_columns(
            reset_password_token_digest: nil,
            reset_password_sent_at:      nil
          )

          render json: { message: "Senha redefinida com sucesso." }, status: :ok
        end

        private

        def valid_token?(user, token)
          return false unless user
          return false unless user.reset_password_token_digest.present?
          return false unless user.reset_password_sent_at&.> 30.minutes.ago

          Digest::SHA256.hexdigest(token.to_s) == user.reset_password_token_digest
        end

        def render_token_error
          render json: { error: "Token inválido ou expirado." }, status: :unprocessable_entity
        end

        def build_reset_link(token, email)
          host = ENV.fetch("APP_HOST", "https://easyhealth.art")
          "#{host}/reset-password?token=#{token}&email=#{CGI.escape(email)}"
        end
      end
    end
  end
end
