# frozen_string_literal: true

Sentry.init do |config|
  config.dsn = ENV["SENTRY_DSN"]

  # Only report errors in staging and production — never in development/test
  config.enabled_environments = %w[staging production]

  config.environment = Rails.env

  # Attach the deploy commit SHA for release tracking
  config.release = ENV["GIT_COMMIT"].presence || ENV["HEROKU_SLUG_COMMIT"].presence

  # Sample 10% of transactions for performance monitoring (adjust per load)
  config.traces_sample_rate = Rails.env.production? ? 0.1 : 0.0

  config.breadcrumbs_logger = [:active_support_logger, :http_logger]

  # Never send raw PII (cookies, session, request bodies)
  config.send_default_pii = false

  # Strip sensitive fields before they reach Sentry
  config.before_send = lambda do |event, _hint|
    event.request&.data = "[FILTERED]" if event.request&.data.is_a?(String)
    event
  end
end
