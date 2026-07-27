require "json"
require "net/http"
require "openssl"
require "uri"

class MakeWebhookClient
  MAX_ATTEMPTS = 5
  MAX_RESPONSE_BODY_BYTES = 20.kilobytes
  SENSITIVE_TEXT_PATTERN = /(authorization|token|secret|api[_-]?key|access[_-]?key)(["'\s:=]+)([^&\s"',}]+)/i

  Result = Struct.new(:status, :error, keyword_init: true) do
    def success?
      status == "accepted_by_make"
    end

    def retryable?
      status == "retrying"
    end
  end

  def self.retry_backoff_for(attempts_count)
    attempts = [ attempts_count.to_i, 1 ].max
    (attempts * attempts).minutes
  end

  def initialize(max_attempts: MAX_ATTEMPTS)
    @max_attempts = max_attempts
  end

  def deliver(user_event, delivery_channels: nil)
    unless MakeWebhookEligibility.deliverable?(user_event)
      reason = MakeWebhookEligibility.ineligibility_reason(user_event)
      user_event.update!(
        make_delivery_status: "disabled",
        make_last_error: reason,
        make_last_error_message: reason,
        make_delivery_channels: channels_for(user_event, delivery_channels),
        make_destination: destination_for(user_event, delivery_channels)
      )
      return Result.new(status: "disabled", error: reason)
    end

    skip_reason = communication_skip_reason(user_event)
    if skip_reason
      log_skipped(user_event, skip_reason)
      user_event.update!(
        make_delivery_status: "skipped",
        make_last_error: skip_reason,
        make_last_error_message: skip_reason,
        make_delivery_channels: channels_for(user_event, delivery_channels),
        make_destination: destination_for(user_event, delivery_channels)
      )
      return Result.new(status: "skipped", error: skip_reason)
    end

    attempt_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    register_attempt(user_event, delivery_channels)

    payload = payload_for(user_event, delivery_channels: delivery_channels)
    body_json = JSON.generate(payload)
    timestamp = Time.current.utc.iso8601
    signature = signature_for(user_event.id, timestamp, body_json)

    log_prepared(user_event, payload)
    response = post(body_json, headers_for(user_event, timestamp, signature, schema_version_for(payload)))
    duration_ms = duration_ms_since(attempt_started_at)

    if response.is_a?(Net::HTTPSuccess)
      mark_accepted(user_event, response, duration_ms)
      track_push_requested_to_make(user_event)
      Result.new(status: "accepted_by_make")
    else
      mark_http_failure(user_event, response, duration_ms)
    end
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    mark_exception(user_event, e, attempt_started_at)
  rescue => e
    mark_exception(user_event, e, attempt_started_at)
  end

  private

  attr_reader :max_attempts

  # A communication event must be known AND enabled with at least one channel.
  # Anything else is recorded as skipped — never sent with an empty/implicit
  # channel list and never given a default channel.
  def communication_skip_reason(user_event)
    name = user_event.event_name
    return "unknown_communication_event" unless CommunicationEvents.known?(name)
    return "communication_event_disabled" unless CommunicationEvents.enabled?(name)

    nil
  end

  def log_prepared(user_event, payload)
    delivery = payload[:delivery] || payload["delivery"] || {}
    channels = delivery[:channels] || delivery["channels"] || []
    Rails.logger.info(
      {
        message: "make_communication_event_prepared",
        event_id: user_event.id,
        event_name: user_event.event_name,
        schema_version: schema_version_for(payload),
        requested_channels: channels,
        user_id: user_event.user_id,
        source: user_event.source
      }.to_json
    )
  end

  def log_skipped(user_event, reason)
    Rails.logger.info(
      {
        message: "make_communication_event_skipped",
        event_id: user_event.id,
        event_name: user_event.event_name,
        reason: reason
      }.to_json
    )
  end

  def log_delivery(user_event)
    Rails.logger.info(
      {
        event: "make_webhook_delivery",
        event_name: user_event.event_name,
        user_event_id: user_event.id,
        user_id: user_event.user_id,
        channel: user_event.make_delivery_channels_list,
        destination: user_event.make_destination,
        attempt: user_event.make_attempts_count,
        delivery_status: user_event.make_delivery_status,
        http_status: user_event.make_last_http_status,
        duration_ms: user_event.make_delivery_duration_ms
      }.to_json
    )
  end

  def register_attempt(user_event, delivery_channels)
    now = Time.current
    user_event.update!(
      make_delivery_status: "sending",
      make_attempts_count: user_event.make_attempts_count.to_i + 1,
      make_first_attempt_at: user_event.make_first_attempt_at || now,
      make_last_attempt_at: now,
      make_next_retry_at: nil,
      make_last_error: nil,
      make_last_error_class: nil,
      make_last_error_message: nil,
      make_delivery_channels: channels_for(user_event, delivery_channels),
      make_destination: destination_for(user_event, delivery_channels)
    )
  end

  def mark_accepted(user_event, response, duration_ms)
    user_event.update!(
      make_delivery_status: "accepted_by_make",
      make_delivered_to_provider_at: Time.current,
      make_last_http_status: response.code.to_i,
      make_last_response_body: sanitized_response_body(response.body),
      make_last_error: nil,
      make_last_error_class: nil,
      make_last_error_message: nil,
      make_delivery_duration_ms: duration_ms,
      make_next_retry_at: nil
    )
    log_delivery(user_event)
  end

  def mark_http_failure(user_event, response, duration_ms)
    error = "Make returned HTTP #{response.code}"
    status = retry_available?(user_event) ? "retrying" : "dead_letter"
    next_retry_at = status == "retrying" ? Time.current + self.class.retry_backoff_for(user_event.make_attempts_count) : nil

    user_event.update!(
      make_delivery_status: status,
      make_last_http_status: response.code.to_i,
      make_last_response_body: sanitized_response_body(response.body),
      make_last_error: error,
      make_last_error_class: nil,
      make_last_error_message: error,
      make_delivery_duration_ms: duration_ms,
      make_next_retry_at: next_retry_at
    )
    log_delivery(user_event)
    Result.new(status: status, error: error)
  end

  def mark_exception(user_event, exception, attempt_started_at)
    status = retry_available?(user_event) ? "retrying" : "failed_to_reach_make"
    next_retry_at = status == "retrying" ? Time.current + self.class.retry_backoff_for(user_event.make_attempts_count) : nil
    error = "#{exception.class}: #{exception.message}"

    user_event.update!(
      make_delivery_status: status,
      make_last_http_status: nil,
      make_last_response_body: nil,
      make_last_error: error.to_s.first(1000),
      make_last_error_class: exception.class.name,
      make_last_error_message: exception.message.to_s.first(1000),
      make_delivery_duration_ms: duration_ms_since(attempt_started_at),
      make_next_retry_at: next_retry_at
    )
    log_delivery(user_event)
    Result.new(status: status, error: error)
  end

  def retry_available?(user_event)
    user_event.make_attempts_count.to_i < max_attempts
  end

  def duration_ms_since(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end

  def sanitized_response_body(body)
    raw = body.to_s
    return nil if raw.blank?

    sanitized = begin
      parsed = JSON.parse(raw)
      JSON.generate(RelationshipEventTracker.sanitize_metadata(parsed))
    rescue JSON::ParserError
      raw.gsub(SENSITIVE_TEXT_PATTERN, "\\1\\2[FILTERED]")
    end
    sanitized.bytesize > MAX_RESPONSE_BODY_BYTES ? sanitized.byteslice(0, MAX_RESPONSE_BODY_BYTES).to_s.scrub : sanitized
  end

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

  def channels_for(user_event, delivery_channels)
    channels = delivery_channels.presence || CommunicationEvents.channels_for(user_event.event_name)
    Array(channels).map(&:to_s).reject(&:blank?)
  rescue CommunicationEvents::ConfigError
    []
  end

  def destination_for(user_event, delivery_channels)
    channels = channels_for(user_event, delivery_channels)
    communication_type = CommunicationEvents.communication_type_for(user_event.event_name).presence
    return communication_type if channels.empty?

    ([ channels.sort.join("-"), communication_type ].compact.join("-")).presence
  rescue CommunicationEvents::ConfigError
    nil
  end
end
