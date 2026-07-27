module Observability
  # Structured JSON logging, emitted on a dedicated stream.
  #
  # This deliberately does NOT replace config.logger. The app already relies on
  # ActiveSupport::TaggedLogging, config.log_tags = [:request_id] and
  # config.silence_healthcheck_path = "/up"; swapping the formatter (or adding
  # lograge, which owns the same hook) would put all three at risk for no gain.
  # Both streams land on stdout, so the Docker json-file driver — and later a
  # log shipper — see one merged stream where JSON lines parse and legacy lines
  # ship as text.
  #
  # PRIVACY: this is an external sink. Never pass an email, name, phone, token,
  # cookie, Authorization header, Google/FCM payload or anything health-related.
  # Identifiers arrive pre-hashed from Observability::Context (*_ref). `metadata`
  # is run through RelationshipEventTracker.sanitize_metadata and then capped.
  module Logger
    SERVICE = "easyhealth-api".freeze

    METADATA_MAX_BYTES = 2_048
    METADATA_MAX_DEPTH = 3

    LEVELS = { debug: 0, info: 1, warn: 2, error: 3 }.freeze

    module_function

    # @param event [String] canonical event name, e.g. "google_auth_failed"
    # @param level [Symbol] :debug | :info | :warn | :error
    # @param metadata [Hash] extra safe fields; sanitized and size-capped
    def emit(event, level: :info, metadata: nil, **fields)
      return unless Observability::Config.enabled?
      return unless emit_level?(level)

      payload = build_payload(event, level, fields, metadata)
      write(payload)
      breadcrumb(event, level, payload)
      payload
    rescue StandardError => e
      # A logging failure must never surface to the caller.
      Rails.logger.warn("[observability] logger failed for #{event}: #{e.class}")
      nil
    end

    def build_payload(event, level, fields, metadata)
      base = {
        ts: Time.current.utc.iso8601(3),
        level: level.to_s,
        event: event.to_s,
        service: SERVICE,
        release: release
      }

      payload = base
        .merge(Observability::Context.to_log_context)
        .merge(fields.symbolize_keys)

      payload[:status_class] = status_class(payload[:status]) if payload[:status]
      payload[:metadata] = safe_metadata(metadata) if metadata.present?

      payload.compact
    end

    # Sanitize with the sanitizer the app already trusts for relationship
    # events, apply the stricter observability denylist on top, then bound the
    # size so one pathological payload cannot blow up a log line.
    def safe_metadata(metadata)
      sanitized = RelationshipEventTracker.sanitize_metadata(metadata || {})
      sanitized = strip_personal(sanitized)
      sanitized = depth_capped(sanitized, METADATA_MAX_DEPTH)

      return { truncated: true } if sanitized.to_json.bytesize > METADATA_MAX_BYTES

      sanitized
    rescue StandardError
      { truncated: true }
    end

    # Observability is stricter than the shared sanitizer, on purpose.
    #
    # RelationshipEventTracker.sanitize_metadata keeps `email`, `name` and
    # `phone` because the Make relationship pipeline exists to send messages to
    # people and genuinely needs them. A log line does not: it is shipped to an
    # external log store and read by whoever has access to it. Same data,
    # different destination, different rule — hence a second pass here rather
    # than tightening the shared sanitizer and breaking the Make payloads.
    PERSONAL_KEY_PATTERN = /(email|e_mail|mail|name|phone|telefone|address|endereco|birth|nascimento|cpf|document|avatar|photo|foto)/i

    # `name` is broad enough to catch first_name/display_name/full_name, which
    # is the point — but it would also swallow legitimately technical keys.
    # These are the ones that identify code, not people.
    TECHNICAL_KEY_ALLOW_LIST = %w[
      event_name job_name check_name class_name table_name column_name
      file_name queue_name integration_name step_name
    ].freeze

    def strip_personal(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), result|
          name = key.to_s
          next if name.match?(PERSONAL_KEY_PATTERN) && !TECHNICAL_KEY_ALLOW_LIST.include?(name)

          result[key] = strip_personal(child)
        end
      when Array
        value.map { |child| strip_personal(child) }
      else
        value
      end
    end

    def depth_capped(value, remaining)
      return "[truncated]" if remaining <= 0

      case value
      when Hash
        value.transform_values { |v| depth_capped(v, remaining - 1) }
      when Array
        value.first(20).map { |v| depth_capped(v, remaining - 1) }
      else
        value
      end
    end

    def status_class(status)
      code = status.to_i
      return "unknown" if code < 100

      "#{code / 100}xx"
    end

    # Specs always see the payload through `collect`; stdout is reserved for
    # environments that actually ship logs somewhere, so test and development
    # output stays readable unless OBSERVABILITY_JSON_LOGS is set.
    def write(payload)
      collected << payload if collecting?
      return unless Observability::Config.json_logs?

      stream.puts(payload.to_json)
      stream.flush if stream.respond_to?(:flush)
    end

    # Sentry already receives the exception; a breadcrumb for each preceding
    # failure gives that exception the chain that led to it.
    def breadcrumb(event, level, payload)
      return unless event.to_s.end_with?("_failed")
      return unless defined?(Sentry) && Sentry.initialized?

      Sentry.add_breadcrumb(
        Sentry::Breadcrumb.new(
          category: "observability",
          message: event.to_s,
          level: level == :error ? "error" : "warning",
          data: payload.slice(:request_id, :route, :result, :error_code, :job_key, :integration_key)
        )
      )
    rescue StandardError
      nil
    end

    def emit_level?(level)
      LEVELS.fetch(level.to_sym, 1) >= LEVELS.fetch(min_level, 1)
    end

    def min_level
      @min_level ||= ENV.fetch("OBSERVABILITY_LOG_LEVEL", "info").to_s.downcase.to_sym
    end

    def release
      ENV["GIT_COMMIT"].presence || ENV["HEROKU_SLUG_COMMIT"].presence
    end

    def stream
      @stream ||= begin
        io = $stdout
        io.sync = true if io.respond_to?(:sync=)
        io
      end
    end

    # ── Test support ─────────────────────────────────────────────────────────
    # Specs assert on structured payloads directly instead of regexing stdout.

    def collecting?
      !@collected.nil?
    end

    def collected
      @collected ||= []
    end

    # Yields the (mutable) buffer as well as returning it, so a spec can hold a
    # reference and assert on it from inside the block — an `around` hook only
    # sees the return value after the example has already finished.
    def collect
      @collected = []
      yield @collected
      @collected
    ensure
      @collected = nil
    end

    def reset!
      @stream = nil
      @min_level = nil
      @collected = nil
    end
  end
end
