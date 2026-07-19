require "json"
require "net/http"
require "openssl"
require "uri"

class MakeWebhookClient
  Result = Struct.new(:status, :error, keyword_init: true) do
    def success?
      status == "delivered"
    end
  end

  def deliver(user_event, delivery_channels: nil)
    unless MakeWebhookEligibility.deliverable?(user_event)
      reason = MakeWebhookEligibility.ineligibility_reason(user_event)
      user_event.update!(make_delivery_status: "disabled", make_last_error: reason)
      return Result.new(status: "disabled", error: reason)
    end

    user_event.update!(
      make_delivery_status: "pending",
      make_attempts_count: user_event.make_attempts_count.to_i + 1,
      make_last_attempt_at: Time.current,
      make_last_error: nil
    )

    payload = payload_for(user_event, delivery_channels: delivery_channels)
    body_json = JSON.generate(payload)
    timestamp = Time.current.utc.iso8601
    signature = signature_for(user_event.id, timestamp, body_json)

    response = post(body_json, headers_for(user_event, timestamp, signature, schema_version_for(payload)))
    if response.is_a?(Net::HTTPSuccess)
      user_event.update!(make_delivery_status: "delivered", make_last_error: nil)
      track_push_requested_to_make(user_event)
      Result.new(status: "delivered")
    else
      error = "HTTP #{response.code}: #{response.body.to_s.first(500)}"
      user_event.update!(make_delivery_status: "failed", make_last_error: error)
      Result.new(status: "failed", error: error)
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    mark_failed(user_event, "timeout: #{e.message}")
  rescue => e
    mark_failed(user_event, "#{e.class}: #{e.message}")
  end

  private

  def post(body_json, headers)
    uri = URI.parse(MakeWebhookEligibility.webhook_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = MakeWebhookEligibility.timeout_seconds
    http.read_timeout = MakeWebhookEligibility.timeout_seconds

    request = Net::HTTP::Post.new(uri.request_uri.presence || "/", headers)
    request.body = body_json
    http.request(request)
  end

  def headers_for(user_event, timestamp, signature, schema_version)
    {
      "Content-Type" => "application/json",
      "X-EasyHealth-Event-Id" => user_event.id.to_s,
      "X-EasyHealth-Event-Name" => user_event.event_name,
      "X-EasyHealth-Schema-Version" => schema_version.to_s,
      "X-EasyHealth-Timestamp" => timestamp,
      "X-EasyHealth-Signature" => signature
    }
  end

  def signature_for(event_id, timestamp, body_json)
    OpenSSL::HMAC.hexdigest(
      "SHA256",
      MakeWebhookEligibility.webhook_secret,
      "#{event_id}.#{timestamp}.#{body_json}"
    )
  end

  def payload_for(user_event, delivery_channels: nil)
    snapshot = payload_snapshot(user_event)
    return snapshot if snapshot && delivery_channels.nil?

    payload = Make::EventPayloadSerializer.new(
      event: user_event,
      delivery_channels: delivery_channels
    ).as_json

    user_event.update!(payload_json: JSON.parse(JSON.generate(payload)))
    payload
  end

  # Funnel: the event was actually delivered to Make. Only push-routed events
  # count; suppressed so it never loops back through the webhook.
  def track_push_requested_to_make(user_event)
    return unless CommunicationEvents.supports_channel?(user_event.event_name, "push")

    PushJourney.track_requested_to_make(
      user: user_event.user,
      event_name: user_event.event_name,
      metadata: { campaign_key: user_event.event_name, source_event_id: user_event.id }
    )
  rescue CommunicationEvents::UnknownEventError
    nil
  end

  def mark_failed(user_event, error)
    user_event.update!(
      make_delivery_status: "failed",
      make_last_error: error.to_s.first(1000)
    )
    Result.new(status: "failed", error: error)
  end

  def payload_snapshot(user_event)
    payload = user_event.payload_json
    return unless payload.is_a?(Hash)
    return unless [ 1, 2 ].include?(payload["schema_version"].to_i)
    return unless payload["event_id"].present?

    payload
  end

  def schema_version_for(payload)
    payload[:schema_version] || payload["schema_version"] || MakeWebhookEligibility.event_schema_version
  end
end
