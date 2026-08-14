require "json"
require "net/http"
require "uri"

module GoogleAds
  # Transport for the Google Ads API REST interface. Knows how to authenticate,
  # how to page through `googleAds:search` and how to fail loudly without ever
  # printing a secret. It knows nothing about campaigns, conversions or metrics.
  #
  # REST (not the google-ads-googleads gem) on purpose: the gem pulls grpc and
  # protobuf, which means native compilation in the Docker image for a feature
  # that issues two read-only queries an hour. `googleauth`/`signet` was already
  # a dependency (FirebasePushService), so authentication costs nothing new.
  #
  # This is a backend-to-Google credential and has nothing to do with the Google
  # Sign-In of EasyHealth users — a different OAuth client, a different scope, a
  # different consent. Nothing here touches user authentication.
  class Client
    # Single point of truth for the API version. A major upgrade is a code
    # change plus a test run, deliberately not an env someone can flip on a
    # server: the GAQL field set is version-specific and a silent bump would
    # break the sync at 3am with no diff to look at.
    API_VERSION = "v25".freeze

    BASE_HOST = "googleads.googleapis.com".freeze
    TOKEN_URI = "https://oauth2.googleapis.com/token".freeze
    SCOPE = "https://www.googleapis.com/auth/adwords".freeze

    OPEN_TIMEOUT = 10
    READ_TIMEOUT = 60

    # A guard against an unbounded loop if the API ever keeps handing back a
    # page token. Two queries over 8 days never approach this.
    MAX_PAGES = 100

    # Transient only. 400/401/403 are configuration or authentication faults:
    # retrying them just delays a log line that someone needs to read.
    RETRYABLE_STATUSES = [ 429, 500, 502, 503, 504 ].freeze
    MAX_RETRIES = 2
    RETRY_BACKOFF_SECONDS = [ 2, 5 ].freeze

    REQUIRED_ENV = %w[
      GOOGLE_ADS_DEVELOPER_TOKEN
      GOOGLE_ADS_CLIENT_ID
      GOOGLE_ADS_CLIENT_SECRET
      GOOGLE_ADS_REFRESH_TOKEN
    ].freeze

    # Carries the HTTP status and Google's request-id so a failure can be taken
    # to Google support. The message is built from Google's own error text,
    # which never contains our credentials.
    class Error < StandardError
      attr_reader :status, :request_id

      def initialize(message, status: nil, request_id: nil)
        @status = status
        @request_id = request_id
        super(message)
      end

      def retryable?
        RETRYABLE_STATUSES.include?(status)
      end
    end

    class NotConfiguredError < Error; end

    class << self
      def configured?
        REQUIRED_ENV.all? { |key| ENV[key].to_s.strip.present? } && customer_id.present?
      end

      # Accepts 123-456-7890 or 1234567890 in the env; the API only ever
      # receives digits.
      def customer_id
        digits(ENV["GOOGLE_ADS_CUSTOMER_ID_EASYHEALTH"].presence || ENV["GOOGLE_ADS_CUSTOMER_ID"])
      end

      # A manager account is optional: an account reachable directly must not be
      # forced through an MCC. The header is sent only when this is set.
      def login_customer_id
        digits(ENV["GOOGLE_ADS_LOGIN_CUSTOMER_ID"])
      end

      def digits(value)
        stripped = value.to_s.gsub(/\D/, "")
        stripped.presence
      end

      def missing_env
        REQUIRED_ENV.reject { |key| ENV[key].to_s.strip.present? } +
          (customer_id.present? ? [] : [ "GOOGLE_ADS_CUSTOMER_ID_EASYHEALTH" ])
      end

      # Test/ops helper: drops the cached OAuth client so new credentials take
      # effect without a restart.
      def reset_credentials!
        mutex.synchronize { @authorizer = nil }
      end

      def access_token
        mutex.synchronize do
          @authorizer ||= build_authorizer
          if @authorizer.access_token.nil? || @authorizer.expires_within?(120)
            @authorizer.fetch_access_token!
          end
          @authorizer.access_token
        end
      end

      private

      def build_authorizer
        require "signet/oauth_2/client"

        Signet::OAuth2::Client.new(
          token_credential_uri: TOKEN_URI,
          client_id: ENV.fetch("GOOGLE_ADS_CLIENT_ID"),
          client_secret: ENV.fetch("GOOGLE_ADS_CLIENT_SECRET"),
          refresh_token: ENV.fetch("GOOGLE_ADS_REFRESH_TOKEN"),
          scope: SCOPE
        )
      end

      def mutex
        @mutex ||= Mutex.new
      end
    end

    # Runs one GAQL query and returns every result row across all pages, as the
    # raw camelCase hashes the REST interface produces.
    def search(query)
      raise NotConfiguredError.new(not_configured_message) unless self.class.configured?

      rows = []
      page_token = nil
      pages = 0

      loop do
        payload = { query: query }
        payload[:pageToken] = page_token if page_token

        body = request_with_retry(payload)
        rows.concat(Array(body["results"]))

        page_token = body["nextPageToken"].presence
        pages += 1
        break if page_token.nil? || pages >= MAX_PAGES
      end

      rows
    end

    def search_url
      "https://#{BASE_HOST}/#{API_VERSION}/customers/#{self.class.customer_id}/googleAds:search"
    end

    private

    def not_configured_message
      "Google Ads não configurado (faltando: #{self.class.missing_env.join(', ')})"
    end

    def request_with_retry(payload)
      attempt = 0

      begin
        perform_search(payload)
      rescue Error => e
        raise unless e.retryable? && attempt < MAX_RETRIES

        delay = RETRY_BACKOFF_SECONDS[attempt] || RETRY_BACKOFF_SECONDS.last
        Rails.logger.warn(
          "[GoogleAds::Client] retrying status=#{e.status} request_id=#{e.request_id || '-'} " \
          "attempt=#{attempt + 1}/#{MAX_RETRIES} in #{delay}s"
        )
        sleep(delay)
        attempt += 1
        retry
      end
    end

    def perform_search(payload)
      uri = URI.parse(search_url)
      response = http_post(uri, headers, JSON.generate(payload))
      status = response.code.to_i
      request_id = response["request-id"]

      unless status == 200
        raise Error.new(
          "GoogleAds API error status=#{status} request_id=#{request_id || '-'} #{summarize_error(response.body)}",
          status: status,
          request_id: request_id
        )
      end

      JSON.parse(response.body.to_s.presence || "{}")
    rescue JSON::ParserError => e
      raise Error.new("GoogleAds API returned invalid JSON: #{e.message}")
    end

    # Authorization / developer-token / refresh token never reach a log line:
    # only the values built here, and nothing here is ever logged.
    def headers
      built = {
        "Authorization" => "Bearer #{self.class.access_token}",
        "developer-token" => ENV.fetch("GOOGLE_ADS_DEVELOPER_TOKEN"),
        "Content-Type" => "application/json"
      }

      login = self.class.login_customer_id
      built["login-customer-id"] = login if login.present?
      built
    end

    # Seam for tests: the only place that touches the network.
    def http_post(uri, headers, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri)
      headers.each { |key, value| request[key] = value }
      request.body = body

      http.request(request)
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      # Treated as transient so the small retry above applies.
      raise Error.new("GoogleAds API timeout: #{e.class}", status: 504)
    end

    # Google's error payload describes the query, not our credentials. Truncated
    # so a verbose validation error cannot flood the log.
    def summarize_error(body)
      parsed = JSON.parse(body.to_s)
      message = parsed.dig("error", "message") || parsed["error"].to_s
      message.to_s.truncate(300)
    rescue JSON::ParserError, TypeError
      body.to_s.truncate(300)
    end
  end
end
