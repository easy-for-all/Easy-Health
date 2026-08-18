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
    attempt_started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    attempt_registered = false

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

    payload = payload_for(user_event, delivery_channels: delivery_channels)
    body_json = JSON.generate(payload)
    timestamp = Time.current.utc.iso8601
    signature = signature_for(user_event.id, timestamp, body_json)

    register_attempt(user_event, delivery_channels)
    attempt_registered = true

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
  rescue Make::EventPayloadSerializer::IncompleteEventError => e
    mark_contract_failure(user_event, e, attempt_started_at,
                          attempt_registered: attempt_registered, delivery_channels: delivery_channels)
  rescue Net::OpenTimeout, Net::ReadTimeout => e
    mark_exception(user_event, e, attempt_started_at,
                   attempt_registered: attempt_registered, delivery_channels: delivery_channels)
  rescue StandardError => e
    mark_exception(user_event, e, attempt_started_at,
                   attempt_registered: attempt_registered, delivery_channels: delivery_channels)
  end

  private

  attr_reader :max_attempts

  # An orchestration event that cannot produce its required payload is a
  # CONTRACT failure, not a transient network problem and not a skip: the fact
  # was born and something in the producer/serializer is broken.
  #
  # It gets exactly ONE retry. Most REQUIRED_CONTEXT fields come from metadata
  # written at creation and are deterministic, but first_workout_completed
  # resolves its session with a DB lookup — and with the :async adapter,
  # perform_later can run before the creating transaction commits. One retry
  # covers that race; after it, the failure is permanent and burning the
  # remaining attempts would only hide it.
  def mark_contract_failure(user_event, error, attempt_started_at, attempt_registered:, delivery_channels:)
    missing_fields = error.message[/fields=(\S+)/, 1].to_s
    attempts = result_attempts_count(user_event, attempt_registered)
    retriable = attempts <= 1
    status = retriable ? "retrying" : "dead_letter"

    Rails.logger.error(
      {
        message: "make_event_contract_failed",
        event_id: user_event.id,
        event_name: user_event.event_name,
        user_id: user_event.user_id,
        error_code: "missing_required_context",
        missing_fields: missing_fields,
        attempts: attempts,
        status: status,
        timestamp: Time.current.utc.iso8601
      }.to_json
    )

    user_event.update!(unregistered_attempt_attrs(user_event, delivery_channels, attempt_registered).merge(
      make_delivery_status: status,
      make_last_http_status: nil,
      make_last_response_body: nil,
      make_last_error: "missing_required_context",
      make_last_error_class: error.class.name,
      make_last_error_message: error.message.to_s.first(1000),
      make_next_retry_at: retriable ? 1.minute.from_now : nil,
      make_delivery_duration_ms: duration_ms_since(attempt_started_at)
    ))

    Result.new(status: status, error: "missing_required_context")
  end

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

  def mark_exception(user_event, exception, attempt_started_at, attempt_registered: true, delivery_channels: nil)
    attempts = result_attempts_count(user_event, attempt_registered)
    status = retry_available_for_attempts?(attempts) ? "retrying" : "failed_to_reach_make"
    next_retry_at = status == "retrying" ? Time.current + self.class.retry_backoff_for(attempts) : nil
    error = "#{exception.class}: #{exception.message}"

    user_event.update!(unregistered_attempt_attrs(user_event, delivery_channels, attempt_registered).merge(
      make_delivery_status: status,
      make_last_http_status: nil,
      make_last_response_body: nil,
      make_last_error: error.to_s.first(1000),
      make_last_error_class: exception.class.name,
      make_last_error_message: exception.message.to_s.first(1000),
      make_delivery_duration_ms: duration_ms_since(attempt_started_at),
      make_next_retry_at: next_retry_at
    ))
    log_delivery(user_event)
    Result.new(status: status, error: error)
  end

  def retry_available?(user_event)
    retry_available_for_attempts?(user_event.make_attempts_count.to_i)
  end

  def retry_available_for_attempts?(attempts)
    attempts < max_attempts
  end

  def result_attempts_count(user_event, attempt_registered)
    attempt_registered ? user_event.make_attempts_count.to_i : user_event.make_attempts_count.to_i + 1
  end

  def unregistered_attempt_attrs(user_event, delivery_channels, attempt_registered)
    return {} if attempt_registered

    now = Time.current
    {
      make_attempts_count: user_event.make_attempts_count.to_i + 1,
      make_first_attempt_at: user_event.make_first_attempt_at || now,
      make_last_attempt_at: now,
      make_delivery_channels: channels_for(user_event, delivery_channels),
      make_destination: destination_for(user_event, delivery_channels)
    }
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
      "X-EasyHealth-Idempotency-Key" => idempotency_key_for(user_event),
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
    if snapshot && delivery_channels.nil? && valid_payload_snapshot?(user_event, snapshot)
      payload = payload_with_idempotency_key(user_event, snapshot)
      persist_payload_json(user_event, payload)
      return payload
    end

    payload = Make::EventPayloadSerializer.new(
      event: user_event,
      # Resolved here so the serializer never has to ask about eligibility.
      # `.presence` keeps the serializer's catalog fallback for the degenerate
      # case where resolution yields nothing.
      delivery_channels: channels_for(user_event, delivery_channels).presence
    ).as_json
    payload = payload_with_idempotency_key(user_event, payload)

    persist_payload_json(user_event, payload)
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
    return unless payload["event_id"].to_s == user_event.id.to_s

    payload
  end

  def valid_payload_snapshot?(user_event, payload)
    return true unless payload["schema_version"].to_i == 2

    required = Make::EventPayloadSerializer::REQUIRED_CONTEXT.fetch(user_event.event_name.to_s, [])
    return true if required.empty?

    context = (payload["context"] || payload[:context] || {}).with_indifferent_access
    required.none? { |field| context[field].blank? }
  end

  def payload_with_idempotency_key(user_event, payload)
    payload = payload.deep_dup
    key = idempotency_key_for(user_event)

    if payload.key?("idempotency_key")
      payload["idempotency_key"] = key
    else
      payload[:idempotency_key] = key
    end

    payload
  end

  def persist_payload_json(user_event, payload)
    normalized = JSON.parse(JSON.generate(payload))
    user_event.update!(payload_json: normalized) unless user_event.payload_json == normalized
  end

  def idempotency_key_for(user_event)
    user_event.idempotency_key.presence || user_event.id.to_s
  end

  def schema_version_for(payload)
    payload[:schema_version] || payload["schema_version"] || MakeWebhookEligibility.event_schema_version
  end

  # The channels EasyHealth decided to EXPOSE to Make for this event, resolved
  # here (not in the serializer, which stays a pure formatter) in order of
  # authority: an explicit override from a smoke test, then what was decided and
  # persisted when the event was born, then a recomputation for legacy rows
  # written before the column existed.
  #
  # This is orchestration channel routing, NOT "deliverable right now". Push is
  # never removed here because the user has no token, has push_enabled=false or
  # has not granted permission — those belong to Make::PushDispatchRequest, at
  # dispatch time. The only gate that narrows a channel at this layer is EMAIL
  # consent, because Make sends email directly and no EasyHealth callback can
  # reapply that rule afterwards.
  def channels_for(user_event, delivery_channels)
    channels = delivery_channels.presence ||
               user_event.make_delivery_channels_list.presence ||
               MakeWebhookEligibility.deliverable_channels(user_event.user, user_event.event_name)
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
