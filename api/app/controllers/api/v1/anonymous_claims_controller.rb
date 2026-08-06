module Api
  module V1
    # O único endpoint do modo anônimo que é AUTENTICADO, e por isso o único que
    # herda de BaseController.
    #
    # As duas metades da prova vêm de lugares diferentes e nenhuma é asserção do
    # cliente: quem é o usuário vem do cookie de sessão recém-criado, e a posse
    # dos dados anônimos vem do token assinado. Um cliente que só tivesse um dos
    # dois não conseguiria reivindicar nada.
    class AnonymousClaimsController < BaseController
      # POST /api/v1/anonymous/claim
      def create
        context = AppInstallations::RequestContext.from(request)
        token = AnonymousSessions::Token.verify(params[:anonymous_token], installation_id: context.installation_id)
        return render json: { status: "invalid_token", reason: token.reason }, status: :unprocessable_entity unless token.valid?

        session = AnonymousOnboardingSession.find_by(id: token.session_id)
        return render json: { status: "nothing_to_claim" }, status: :ok if session.nil?

        result = AnonymousSessions::ClaimToUser.new(user: current_user, session: session).call

        render json: {
          status: result.status.to_s,
          plans_claimed: result.plans_claimed,
          sessions_claimed: result.sessions_claimed,
          failure_code: result.failure_code
        }.compact, status: status_for(result)
      end

      private

      # Um claim que falhou por conflito é PERMANENTE: repetir dá o mesmo
      # resultado, e o cliente precisa parar de tentar em vez de manter um
      # marcador pendente para sempre.
      def status_for(result)
        return :ok if result.success
        return :conflict if result.status == :conflict

        :unprocessable_entity
      end
    end
  end
end
