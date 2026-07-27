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

  # Strip sensitive fields before they reach Sentry, then attach the correlation
  # tags so an exception here can be tied to a structured log line, a
  # server-side event and an incident by request_id.
  #
  # Only refs and low-cardinality dimensions — Observability::Context.sentry_tags
  # hashes installation/session ids and never exposes an email. The masked user
  # context set by Api::V1::BaseController is untouched.
  config.before_send = lambda do |event, _hint|
    event.request&.data = "[FILTERED]" if event.request&.data.is_a?(String)

    begin
      tags = Observability::Context.sentry_tags
      event.tags = (event.tags || {}).merge(tags) if tags.present?
    rescue StandardError
      # Never let tagging drop an error report.
    end

    event
  end
end
