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
end
