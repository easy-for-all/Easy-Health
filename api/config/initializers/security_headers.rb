Rails.application.config.action_dispatch.default_headers.merge!(
  "X-Frame-Options"             => "DENY",
  "X-Content-Type-Options"      => "nosniff",
  "Referrer-Policy"             => "strict-origin-when-cross-origin",
  "Permissions-Policy"          => "camera=(), microphone=(), geolocation=()",
  "Cross-Origin-Opener-Policy"  => "same-origin",
  "Strict-Transport-Security"   => "max-age=31536000; includeSubDomains"
)
