class Rack::Attack
  # General throttle: 300 requests per 5 minutes per IP
  throttle("req/ip", limit: 300, period: 5.minutes) do |req|
    req.ip
  end

  # Brute-force protection on login: 10 attempts per minute per IP
  throttle("login/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/rails/users/sign_in" && req.post?
  end

  # Registration spam protection: 5 attempts per minute per IP
  throttle("signup/ip", limit: 5, period: 1.minute) do |req|
    req.ip if req.path == "/rails/users" && req.post?
  end

  # Mobile OAuth code exchange: short burst allowance, avoids brute forcing
  # one-time codes while keeping the happy path responsive.
  throttle("mobile-auth-exchange/ip", limit: 20, period: 1.minute) do |req|
    req.ip if req.path == "/api/v1/auth/mobile/exchange" && req.post?
  end

  # Analytics ingestion: batches are cheap but must not be abused. Generous
  # enough for a normal session (each POST carries up to 50 events).
  throttle("analytics-events/ip", limit: 120, period: 1.minute) do |req|
    req.ip if req.path == "/api/v1/analytics/events" && req.post?
  end

  # App installation register/refresh: idempotent upsert, called on boot and on
  # a few lifecycle transitions. Not a hot path per install.
  throttle("app-installations/ip", limit: 60, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/v1/app/installations") && (req.post? || req.patch?)
  end

  # Modo anônimo. Estes três são a única superfície do sistema onde uma
  # requisição SEM autenticação nenhuma pode provocar uma chamada paga a um
  # provedor de IA — por isso os limites são apertados e por IP e por aparelho.
  #
  # Não substituem o contador por instalação nem o disjuntor global (ver
  # AnonymousSessions::GeneratePlan): estes protegem contra volume, aqueles
  # contra custo. Um atacante com muitos IPs passa por aqui e ainda assim para
  # no teto global.
  throttle("anonymous-sessions/ip", limit: 20, period: 1.hour) do |req|
    req.ip if req.path == "/api/v1/anonymous/sessions" && req.post?
  end

  throttle("anonymous-generate/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.path == "/api/v1/anonymous/workout_plan/generate" && req.post?
  end

  # Por aparelho, não por IP: um prédio inteiro atrás de um NAT compartilha IP,
  # e limitar só por IP puniria vizinhos legítimos.
  throttle("anonymous-generate/installation", limit: 5, period: 1.hour) do |req|
    if req.path == "/api/v1/anonymous/workout_plan/generate" && req.post?
      req.get_header("HTTP_X_INSTALLATION_ID").presence
    end
  end

  self.throttled_responder = lambda do |_req|
    [
      429,
      { "Content-Type" => "application/json" },
      [ '{"error":"Too Many Requests"}' ]
    ]
  end
end
