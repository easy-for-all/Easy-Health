# Autentica shells nativos que não conseguem carregar o cookie do Devise.
#
# O app iOS embarca os assets web dentro do IPA (App Store 2.5.2), então a
# origem é capacitor://localhost e não easyhealth.art. O cookie de sessão é
# SameSite=Lax e não viaja nessas requisições cross-site; abrir para
# SameSite=None enfraqueceria Web/Android e ainda assim perderia para o
# bloqueio de cookie de terceiros do WKWebView. Ver MobileSession.
#
# Aditivo por construção: sem o header Authorization o concern não faz nada e
# o caminho de cookie de Web/Android continua idêntico. É por isso que ele pode
# viver no ApplicationController sem risco para o que já existe.
#
# O prefixo ehs_ NÃO é decoração. Outros fluxos já usam Authorization: Bearer
# neste mesmo nível — AnonymousAuthentication, e os controllers de integração
# do Make. Sem o guard de prefixo, um token anônimo perfeitamente válido cairia
# aqui e receberia 401 antes de chegar no concern que sabe lê-lo.
module MobileSessionAuthentication
  extend ActiveSupport::Concern

  # Opt-in explícito. Sem ele o servidor não emite token nenhum, então o bundle
  # web normal nunca recebe um bearer token que ficaria exposto a XSS sem ter
  # utilidade alguma — o cookie httponly já resolve o caso dele.
  ISSUE_HEADER = "X-EasyHealth-Mobile-Session".freeze

  included do
    before_action :authenticate_mobile_session!
  end

  private

  attr_reader :current_mobile_session

  def authenticate_mobile_session!
    token = mobile_session_bearer_token
    return if token.blank?

    session = MobileSession.authenticate(token)

    # Token apresentado e inválido é erro, não fallback silencioso: cair para
    # "não autenticado" faria o cliente ver 401 em endpoints aleatórios sem
    # nunca descobrir que o problema é a sessão dele. Aqui ele sabe o que fazer.
    if session.nil?
      render json: {
        error: "invalid_mobile_session",
        message: "Sua sessão expirou. Entre novamente para continuar."
      }, status: :unauthorized
      return
    end

    @current_mobile_session = session
    # store: false — não queremos escrever cookie de sessão numa requisição que
    # se autenticou por token. O warden resolve current_user só para esta
    # request, que é exatamente o contrato de um cliente stateless.
    sign_in(:user, session.user, store: false)
  end

  def mobile_session_bearer_token
    raw = request.headers["Authorization"].to_s[/\ABearer\s+(.+)\z/i, 1].to_s.strip
    return "" unless raw.start_with?(MobileSession::TOKEN_PREFIX)

    raw
  end

  # Emite um token de sessão mobile quando o cliente pediu por ele. Devolve nil
  # para todo mundo que não pediu, e o caller simplesmente não inclui a chave.
  def issue_mobile_session_for(user)
    return nil unless mobile_session_requested?

    MobileSession.issue_for!(
      user: user,
      platform: mobile_session_platform,
      installation_id: request.headers["X-Installation-Id"].presence,
      app_version: request.headers["X-App-Version"].presence
    )
  rescue MobileSession::InvalidPlatformError
    # Pediu sessão mobile sem dizer de qual plataforma. Não é motivo para
    # derrubar um login que, no resto, deu certo — o cliente cai no cookie.
    Rails.logger.warn("[MobileSession] issue skipped: invalid platform header")
    nil
  end

  def mobile_session_requested?
    ActiveModel::Type::Boolean.new.cast(request.headers[ISSUE_HEADER]).present?
  end

  def mobile_session_platform
    request.headers["X-Platform"].presence || request.headers["X-EasyHealth-Platform"].presence
  end

  # Açúcar para os controllers de auth: mescla a chave só quando ela existe.
  def with_mobile_session(payload, user)
    token = issue_mobile_session_for(user)
    return payload if token.blank?

    payload.merge(mobile_session_token: token)
  end
end
