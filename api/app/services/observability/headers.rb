module Observability
  # Parses and sanitizes the correlation headers sent by the client.
  #
  # SECURITY CONTRACT — read before adding a header here:
  #   * Every value below is client-controlled. It is used for grouping and
  #     diagnostics ONLY. It is never used for authorization, never trusted to
  #     identify a user, and never used to look up a record the caller has not
  #     already been authorized for. Devise and `require_admin!` remain the only
  #     authority.
  #   * Truncate first, then validate. A value that fails validation is dropped
  #     (nil / "unknown"), never "cleaned up and kept" — a sanitized-but-kept
  #     value is exactly how hostile input reaches a label or a log field.
  #   * app_version/app_build/platform end up as low-cardinality dimensions, so
  #     the patterns are deliberately strict.
  module Headers
    REQUEST_ID  = "X-Request-Id".freeze
    INSTALLATION = "X-Installation-Id".freeze
    SESSION     = "X-Session-Id".freeze
    PLATFORM    = "X-Platform".freeze
    APP_VERSION = "X-App-Version".freeze
    APP_BUILD   = "X-App-Build".freeze

    # Opaque identifiers: uuid, ulid, nanoid and Rails' own request ids all fit.
    IDENTIFIER_PATTERN = /\A[A-Za-z0-9._:-]+\z/
    VERSION_PATTERN    = /\A[0-9]+(\.[0-9]+){0,3}\z/
    BUILD_PATTERN      = /\A[0-9]{1,9}\z/

    IDENTIFIER_MAX = 64
    VERSION_MAX    = 32
    BUILD_MAX      = 16
    PLATFORM_MAX   = 16

    module_function

    def identifier(headers, name)
      constrained(headers[name], max: identifier_max(name), pattern: IDENTIFIER_PATTERN)
    end

    def platform(headers)
      value = constrained(headers[PLATFORM], max: PLATFORM_MAX, pattern: IDENTIFIER_PATTERN)
      return nil if value.nil?

      normalized = value.downcase
      Analytics::EventCatalog::PLATFORMS.include?(normalized) ? normalized : "unknown"
    end

    def app_version(headers)
      constrained(headers[APP_VERSION], max: VERSION_MAX, pattern: VERSION_PATTERN)
    end

    def app_build(headers)
      constrained(headers[APP_BUILD], max: BUILD_MAX, pattern: BUILD_PATTERN)
    end

    # Truncate, then validate. Returns nil for anything that does not match.
    def constrained(raw, max:, pattern:)
      value = raw.to_s.strip
      return nil if value.empty?

      value = value[0, max]
      return nil unless value.match?(pattern)

      value
    end

    def identifier_max(name)
      return AppInstallation::INSTALLATION_ID_MAX_BYTES if name == INSTALLATION

      IDENTIFIER_MAX
    rescue NameError
      IDENTIFIER_MAX
    end
  end
end
