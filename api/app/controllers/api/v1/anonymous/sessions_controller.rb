module Api
  module V1
    module Anonymous
      # Emite o token da sessão anônima. É o único endpoint anônimo sem token —
      # por isso não herda de Anonymous::BaseController.
      #
      # A instalação precisa JÁ EXISTIR em app_installations, criada pelo
      # register do boot do app. Sem essa pré-condição qualquer cliente poderia
      # inventar um installation_id e abrir uma torneira de geração; com ela, o
      # caminho para gerar passa obrigatoriamente pelo mesmo funil que o painel
      # já contabiliza.
      class SessionsController < ApplicationController
        # POST /api/v1/anonymous/sessions
        def create
          return render_unavailable("disabled") unless AnonymousSessions.enabled?

          context = AppInstallations::RequestContext.from(request)
          installation_id = params[:installation_id].to_s.strip.presence || context.installation_id

          return render_rejected("invalid_installation_id") if installation_id.blank?
          return render_rejected("not_native") unless context.native?
          return render_rejected("build_too_old") unless AnonymousSessions.build_eligible?(context.build_number)

          installation = AppInstallation.find_by(installation_id: installation_id)
          return render_rejected("installation_not_found") if installation.nil?
          return render_rejected("not_android") unless installation.platform == "android"

          # Instalação já vinculada a uma conta não volta a ser anônima. Deixar
          # voltaria a abrir um caminho de escrita sem usuário para dados que já
          # têm dono.
          return render_rejected("already_linked") if installation.user_id.present?

          session = find_or_create_session(installation)
          return render_unavailable("session_unavailable") if session.nil?
          return render_rejected("session_claimed") if session.claimed?

          render json: {
            token: AnonymousSessions::Token.issue(session_id: session.id, installation_id: installation_id),
            expires_at: AnonymousSessions::Token.expires_at.iso8601,
            plans_remaining: session.plans_remaining
          }, status: :created
        rescue StandardError => e
          Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
          Rails.logger.error("[anonymous] session mint error: #{e.class}: #{e.message}")
          render_unavailable("internal_error")
        end

        private

        # O índice único em app_installation_id é o árbitro da corrida: dois
        # boots simultâneos do mesmo aparelho não podem criar duas sessões, ou
        # o limite de 3 viraria 6.
        def find_or_create_session(installation)
          AnonymousOnboardingSession.find_or_create_by!(app_installation: installation)
        rescue ActiveRecord::RecordNotUnique
          AnonymousOnboardingSession.find_by(app_installation: installation)
        end

        def render_rejected(reason)
          render json: { error: "anonymous_session_rejected", reason: reason, retryable: false },
                 status: :unprocessable_entity
        end

        def render_unavailable(reason)
          render json: { error: "anonymous_mode_unavailable", reason: reason, retryable: true },
                 status: :service_unavailable
        end
      end
    end
  end
end
