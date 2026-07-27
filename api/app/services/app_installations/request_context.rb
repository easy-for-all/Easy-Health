module AppInstallations
  # Reads the installation context out of an HTTP request. Pure: never writes,
  # never authenticates, never associates.
  #
  # Exists to end a real divergence: the reconciliation concern used to read
  # X-Installation-Id raw while Observability::Headers truncated it at 64 chars,
  # so an id the register accepted (up to 128 bytes) could be linked but stay
  # invisible to observability. Both now go through the same truncate-then-
  # validate contract, bounded by AppInstallation::INSTALLATION_ID_MAX_BYTES.
  #
  # build_number is exposed as DESCRIPTIVE METADATA ONLY. It must never gate
  # reconciliation: the Android shell loads a remote web bundle, so a build 34
  # shell running today's bundle sends exactly the same header as a build 47.
  class RequestContext
    # X-Platform -> runtime_context. "android" maps to android_native because the
    # only Android client is the Capacitor shell, and only it generates an
    # installation_id. "android_webview" is never produced: a bridged WebView is
    # indistinguishable from a plain one on the server side.
    RUNTIME_BY_PLATFORM = {
      "android" => "android_native",
      "web" => "web",
      "pwa" => "pwa"
    }.freeze

    UNKNOWN_RUNTIME = "unknown".freeze

    attr_reader :installation_id, :runtime_context, :build_number

    def self.from(request)
      headers = request.headers

      new(
        installation_id: Observability::Headers.constrained(
          headers[Observability::Headers::INSTALLATION],
          max: AppInstallation::INSTALLATION_ID_MAX_BYTES,
          pattern: Observability::Headers::IDENTIFIER_PATTERN
        ),
        platform: Observability::Headers.platform(headers),
        build_number: Observability::Headers.app_build(headers)
      )
    rescue StandardError
      # Reading diagnostics must never break a request.
      new(installation_id: nil, platform: nil, build_number: nil)
    end

    def initialize(installation_id:, platform: nil, build_number: nil)
      @installation_id = installation_id.presence
      @runtime_context = RUNTIME_BY_PLATFORM.fetch(platform.to_s, UNKNOWN_RUNTIME)
      @build_number = build_number.presence
    end

    def present?
      @installation_id.present?
    end

    def native?
      @runtime_context == "android_native"
    end

    # Short, non-reversible fingerprint for logs. The full installation_id is a
    # stable device identifier and never belongs in a log line.
    def installation_id_hash
      return nil if @installation_id.nil?

      Digest::SHA256.hexdigest(@installation_id)[0, 12]
    end
  end
end
