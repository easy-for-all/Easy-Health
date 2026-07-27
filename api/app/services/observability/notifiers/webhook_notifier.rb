module Observability
  module Notifiers
    # Posts an incident payload to a configured HTTPS endpoint.
    #
    # Small on purpose: a hard timeout, one attempt, no retry queue. If an alert
    # webhook is slow or down, the correct behaviour is to give up and log —
    # blocking the health-check run to retry an alert would mean the checker
    # stops checking, which is a worse outcome than a missed notification.
    class WebhookNotifier
      DEFAULT_TIMEOUT = 5

      def initialize(url:, token: nil, timeout: nil)
        @url = url
        @token = token || Observability::Config.alert_webhook_token
        @timeout = timeout || Observability::Config.alert_webhook_timeout_seconds
      end

      # @return [Boolean] delivered successfully
      def call(payload:)
        uri = URI.parse(@url)
        unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
          Rails.logger.warn("[observability] alert webhook URL is not http(s)")
          return false
        end

        if Rails.env.production? && !uri.is_a?(URI::HTTPS)
          Rails.logger.warn("[observability] refusing to send alert over plain HTTP in production")
          return false
        end

        response = post(uri, payload)
        success = response.is_a?(Net::HTTPSuccess)

        unless success
          # Status code only — a response body from a third party is untrusted
          # input and has no place in our logs.
          Rails.logger.warn("[observability] alert webhook responded #{response&.code}")
        end

        success
      rescue StandardError => e
        Rails.logger.warn("[observability] alert webhook error: #{e.class}")
        false
      end

      private

      def post(uri, payload)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.is_a?(URI::HTTPS)
        http.open_timeout = @timeout
        http.read_timeout = @timeout

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = "Bearer #{@token}" if @token.present?
        request.body = payload.to_json

        http.request(request)
      end
    end
  end
end
