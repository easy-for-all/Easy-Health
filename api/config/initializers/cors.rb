Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    configured_origins = ENV.fetch("CORS_ORIGINS", "http://localhost:3000").split(",").map(&:strip)
    local_origins = Rails.env.development? ? [/\Ahttp:\/\/(?:localhost|127\.0\.0\.1):\d+\z/] : []

    origins(*configured_origins, *local_origins)

    resource "*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: true
  end

  # Shells nativos com bundle local. A origem deles não é easyhealth.art, então
  # eles não caem no bloco acima — e não devem cair.
  #
  # credentials: false de propósito. Este caminho se autentica pelo header
  # Authorization: Bearer ehs_... (ver MobileSessionAuthentication), nunca por
  # cookie. Marcar false aqui é o que impede que uma origem local passe a
  # carregar a sessão de cookie do domínio principal, que é exatamente o
  # afrouxamento que não queremos fazer para viabilizar o app.
  allow do
    origins(
      "capacitor://localhost",  # iOS
      "ionic://localhost",      # iOS, esquema legado do Capacitor
      "http://localhost"        # Android com bundle local
    )

    resource "*",
      headers: :any,
      methods: [:get, :post, :put, :patch, :delete, :options, :head],
      credentials: false
  end
end
