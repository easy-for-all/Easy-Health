require "net/http"
require "json"
require "base64"
require "stringio"

# Isolated FCM HTTP v1 sender. Obtains an OAuth2 access token from a Firebase
# Service Account (via googleauth) and posts a single message per device token.
#
# Security:
# - Credentials come from ENV only (FIREBASE_SERVICE_ACCOUNT_JSON[_BASE64]),
#   never persisted in the DB.
# - The device token is NEVER written to logs (masked).
#
# Returns a Result with a structured status so callers can invalidate dead
# tokens (UNREGISTERED / INVALID_ARGUMENT) without inspecting HTTP internals.
class FirebasePushService
  FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging".freeze
  ENDPOINT_TEMPLATE = "https://fcm.googleapis.com/v1/projects/%s/messages:send".freeze
  # FCM error statuses that mean "this token is dead, stop using it".
  INVALID_TOKEN_ERRORS = %w[UNREGISTERED INVALID_ARGUMENT SENDER_ID_MISMATCH].freeze

  Result = Struct.new(:status, :message_id, :error_code, :invalid_token, keyword_init: true) do
    def sent?    = status == "sent"
    def failed?  = status == "failed"
  end

  class << self
    def service_account_hash
      raw = ENV["FIREBASE_SERVICE_ACCOUNT_JSON"].presence
      raw ||= decode_base64(ENV["FIREBASE_SERVICE_ACCOUNT_JSON_BASE64"])
      return nil if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError => e
      Rails.logger.error("[FirebasePushService] Invalid service account JSON: #{e.message}")
      nil
    end

    def project_id
      ENV["FIREBASE_PROJECT_ID"].presence || service_account_hash&.dig("project_id")
    end

    def configured?
      service_account_hash.present? && project_id.present?
    end

    private

    def decode_base64(value)
      return nil if value.blank?

      Base64.decode64(value)
    end
  end

  def deliver(token:, title:, body:, data: {})
    return unconfigured_result unless self.class.configured?
    return Result.new(status: "failed", error_code: "missing_token", invalid_token: true) if token.blank?

    response = post_message(build_message(token:, title:, body:, data:))
    interpret(response)
  rescue => e
    Rails.logger.error("[FirebasePushService] send error for token #{masked(token)}: #{e.class}: #{e.message}")
    Result.new(status: "failed", error_code: "exception", invalid_token: false)
  end

  private

  def build_message(token:, title:, body:, data:)
    {
      message: {
        token: token,
        notification: { title: title, body: body },
        # FCM data values must all be strings.
        data: data.transform_values(&:to_s),
        android: { priority: "high", notification: { channel_id: "workout_reminders" } }
      }
    }
  end

  def post_message(payload)
    uri = URI(format(ENDPOINT_TEMPLATE, self.class.project_id))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 5
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{access_token}"
    request["Content-Type"] = "application/json"
    request.body = payload.to_json
    http.request(request)
  end

  def interpret(response)
    code = response.code.to_i
    body = parse_body(response.body)

    if code == 200
      Result.new(status: "sent", message_id: body["name"], invalid_token: false)
    else
      fcm_status = body.dig("error", "details", 0, "errorCode") || body.dig("error", "status")
      Result.new(
        status: "failed",
        error_code: fcm_status || "http_#{code}",
        invalid_token: INVALID_TOKEN_ERRORS.include?(fcm_status) || code == 404
      )
    end
  end

  def parse_body(raw)
    JSON.parse(raw.to_s)
  rescue JSON::ParserError
    {}
  end

  # Access token cached at class level (~1h TTL from Google) with a mutex, since
  # Puma serves requests across threads.
  def access_token
    self.class.access_token
  end

  def unconfigured_result
    Result.new(status: "failed", error_code: "not_configured", invalid_token: false)
  end

  def masked(token)
    return "nil" if token.blank?

    "#{token[0, 6]}…#{token[-4, 4]}"
  end

  class << self
    def access_token
      mutex.synchronize do
        @authorizer ||= build_authorizer
        # Signet refreshes automatically when the token is missing/expired.
        @authorizer.fetch_access_token! if @authorizer.access_token.nil? || @authorizer.expires_within?(120)
        @authorizer.access_token
      end
    end

    # Test/ops helper: drop the cached authorizer so new credentials take effect.
    def reset_credentials!
      mutex.synchronize { @authorizer = nil }
    end

    private

    def build_authorizer
      Google::Auth::ServiceAccountCredentials.make_creds(
        json_key_io: StringIO.new(service_account_hash.to_json),
        scope: FCM_SCOPE
      )
    end

    def mutex
      @mutex ||= Mutex.new
    end
  end
end
