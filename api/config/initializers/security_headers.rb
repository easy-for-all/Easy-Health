Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Frame-Options"             => "DENY",
  "X-Content-Type-Options"      => "nosniff",
  "Referrer-Policy"             => "strict-origin-when-cross-origin",
  "Permissions-Policy"          => "camera=(), microphone=(), geolocation=()",
  "Cross-Origin-Opener-Policy"  => "same-origin",
  "Strict-Transport-Security"   => "max-age=31536000; includeSubDomains"
)

# Remove Server header set by Puma/Thruster at HTTP level (not reachable via default_headers)
Rails.application.config.middleware.insert_before 0, Class.new {
  def initialize(app) = (@app = app)
  def call(env)
    status, headers, body = @app.call(env)
    headers.delete("Server")
    headers.delete("X-Powered-By")
    [status, headers, body]
  end
}
