# frozen_string_literal: true

# Populates Observability::Context for every HTTP request and emits exactly one
# `http_request_completed` record on the way out.
#
# Why Rack middleware instead of a controller concern:
#   * Not every controller descends from ApplicationController —
#     Api::V1::Integrations::Make::PushDispatchesController inherits
#     ActionController::API directly, so a concern would silently skip it.
#   * duration/status must cover requests that never reach a controller at all:
#     rack-attack 429s, routing-error 404s, and exceptions rendered by
#     ShowExceptions. Only an `ensure` out here sees those.
#   * AppInstallationReconciliation is an after_action; this `ensure` runs
#     strictly after it, so the log line can report the outcome of the link.
#
# Why it lives in lib/middleware and not app/middleware: config/application.rb
# needs the actual constant at boot (MiddlewareStack calls `klass.new`, it does
# not constantize strings), and autoloaded constants cannot be referenced during
# initialization. lib/middleware is excluded from autoload_lib and required
# explicitly instead.
#
# Nothing in here may break a request. Every block is guarded; a failure in the
# observability layer degrades to a warn log.
class ObservabilityRequestContext
  REQUEST_ID_HEADER = "X-Request-Id"

  # Paths that would otherwise dominate the log stream with no diagnostic value.
  # Mirrors config.silence_healthcheck_path.
  SKIP_LOG_PATHS = [ "/up", "/internal/metrics" ].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    started = monotonic_now
    request = ActionDispatch::Request.new(env)

    populate(request)

    status, headers, body = @app.call(env)
    [ status, finish(request, env, status, headers, started), body ]
  rescue Exception => e # rubocop:disable Lint/RescueException
    # Report the failed request, then let the exception continue untouched.
    finish(request, env, 500, nil, started, error_class: e.class.name)
    raise
  ensure
    Observability::Context.reset
  end

  private

  def populate(request)
    Observability::Context.reset

    headers = request.headers
    context = Observability::Context

    context.request_id     = request_id_for(request, headers)
    context.trace_id       = context.request_id
    context.installation_id = Observability::Headers.identifier(headers, Observability::Headers::INSTALLATION)
    context.session_id     = Observability::Headers.identifier(headers, Observability::Headers::SESSION)
    context.platform       = Observability::Headers.platform(headers)
    context.app_version    = Observability::Headers.app_version(headers)
    context.app_build      = Observability::Headers.app_build(headers)
    context.environment    = Rails.env.to_s
    context.source         = "http"
    context.started_at     = Time.current
  rescue StandardError => e
    warn_failure("populate", e)
  end

  # Rails' own ActionDispatch::RequestId already validated and/or generated
  # request.request_id, so an absent or malformed X-Request-Id still yields a
  # usable value without us trusting the client's string.
  def request_id_for(request, headers)
    Observability::Headers.identifier(headers, Observability::Headers::REQUEST_ID) ||
      request.request_id
  end

  # Returns the (possibly amended) response headers.
  def finish(request, env, status, headers, started, error_class: nil)
    duration_ms = ((monotonic_now - started) * 1000).round(2)

    enrich_from_response(request, env)

    unless skip?(request)
      Observability::HttpStats.record(status: status, duration_ms: duration_ms)
      Observability::Logger.emit(
        "http_request_completed",
        level: status.to_i >= 500 ? :error : :info,
        status: status,
        duration_ms: duration_ms,
        result: result_for(status),
        error_code: error_class
      )
    end

    stamp_request_id(headers)
  rescue StandardError => e
    warn_failure("finish", e)
    headers
  end

  # route/controller/action and the resolved user are only knowable once the
  # request has been dispatched.
  def enrich_from_response(request, env)
    context = Observability::Context
    context.route = Observability::RouteNormalizer.call(request)

    instance = env["action_controller.instance"]
    if instance
      context.controller ||= safe_call(instance, :controller_name)
      context.action     ||= safe_call(instance, :action_name)
    end

    context.user_id ||= current_user_id(env)
  rescue StandardError => e
    warn_failure("enrich", e)
  end

  # Reads the already-authenticated user without running Warden strategies:
  # `user` only deserializes an existing session, so this never triggers a login
  # attempt, never writes, and never changes the response. It gives us user
  # correlation on controllers we do not touch at all — omniauth callbacks and
  # the Stripe webhook included.
  def current_user_id(env)
    warden = env["warden"]
    return nil if warden.nil?

    warden.user(:user)&.id
  rescue StandardError
    nil
  end

  def stamp_request_id(headers)
    return headers if headers.nil?

    headers[REQUEST_ID_HEADER] ||= Observability::Context.request_id
    headers
  end

  def skip?(request)
    SKIP_LOG_PATHS.include?(request.path)
  rescue StandardError
    false
  end

  def result_for(status)
    code = status.to_i
    return "success" if code < 400
    return "client_error" if code < 500

    "server_error"
  end

  def safe_call(object, method)
    object.public_send(method) if object.respond_to?(method)
  rescue StandardError
    nil
  end

  def monotonic_now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def warn_failure(stage, error)
    Rails.logger.warn("[observability] request_context #{stage} failed: #{error.class}")
  end
end
