# Autentica uma sessão anônima a partir do Bearer token + header de instalação.
#
# Este concern NUNCA é incluído em Api::V1::BaseController. A regra do projeto é
# que um controller ou exige sessão (herda BaseController) ou é anônimo (herda
# Api::V1::Anonymous::BaseController), nunca os dois. Um `skip_before_action
# :authenticate_user!` num controller autenticado é como uma rota protegida vira
# pública sem ninguém notar — existe um spec que falha se isso aparecer.
module AnonymousAuthentication
  extend ActiveSupport::Concern

  # Erros que o cliente PODE tratar: renovar o token, parar de tentar, ou
  # mandar a pessoa criar conta.
  UNAUTHORIZED_REASONS = %w[
    missing_token invalid_token expired_token installation_mismatch
    installation_not_found session_claimed not_native build_too_old
  ].freeze

  included do
    before_action :authenticate_anonymous!
  end

  private

  attr_reader :anonymous_session, :anonymous_installation

  def authenticate_anonymous!
    return render_anonymous_unauthorized("disabled") unless AnonymousSessions.enabled?

    context = AppInstallations::RequestContext.from(request)
    return render_anonymous_unauthorized("missing_token") if context.installation_id.blank?

    # O modo anônimo é exclusivo do Android nativo. Web e PWA seguem exigindo
    # conta — o experimento não os toca, e abrir aqui abriria para eles também.
    return render_anonymous_unauthorized("not_native") unless context.native?
    return render_anonymous_unauthorized("build_too_old") unless AnonymousSessions.build_eligible?(context.build_number)

    result = AnonymousSessions::Token.verify(bearer_token, installation_id: context.installation_id)
    return render_anonymous_unauthorized(result.reason) unless result.valid?

    session = AnonymousOnboardingSession.includes(:app_installation).find_by(id: result.session_id)
    return render_anonymous_unauthorized("installation_not_found") if session.nil?

    # O token continua criptograficamente válido depois do cadastro; o que muda
    # é que os dados já têm dono. Continuar aceitando aqui daria dois caminhos
    # de escrita para o mesmo plano, um deles sem usuário.
    return render_anonymous_unauthorized("session_claimed") if session.claimed?

    # A instalação do token tem que ser a instalação do header. Sem esta
    # checagem, um token válido de OUTRA instalação passaria pela verificação
    # de assinatura e escreveria no plano errado.
    return render_anonymous_unauthorized("installation_mismatch") if
      session.app_installation.installation_id != context.installation_id

    @anonymous_session = session
    @anonymous_installation = session.app_installation
  end

  def bearer_token
    request.headers["Authorization"].to_s.sub(/\Abearer\s+/i, "")
  end

  def render_anonymous_unauthorized(reason)
    render json: { error: "anonymous_session_invalid", reason: reason }, status: :unauthorized
  end
end
