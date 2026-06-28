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

  def deliver(user_event)
    unless MakeWebhookEligibility.deliverable?(user_event)
      reason = MakeWebhookEligibility.ineligibility_reason(user_event)
      user_event.update!(make_delivery_status: "disabled", make_last_error: reason)
      return Result.new(status: "disabled", error: reason)
    end

    body_json = JSON.generate(payload_for(user_event))
    timestamp = Time.current.utc.iso8601
    signature = signature_for(user_event.id, timestamp, body_json)

    user_event.update!(
      make_delivery_status: "pending",
      make_attempts_count: user_event.make_attempts_count.to_i + 1,
      make_last_attempt_at: Time.current,
      make_last_error: nil
    )

    response = post(body_json, headers_for(user_event, timestamp, signature))
    if response.is_a?(Net::HTTPSuccess)
      user_event.update!(make_delivery_status: "delivered", make_last_error: nil)
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

  def headers_for(user_event, timestamp, signature)
    {
      "Content-Type" => "application/json",
      "X-EasyHealth-Event-Id" => user_event.id.to_s,
      "X-EasyHealth-Event-Name" => user_event.event_name,
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

  def payload_for(user_event)
    user = user_event.user
    {
      event_id: user_event.id,
      event_name: user_event.event_name,
      occurred_at: user_event.occurred_at&.iso8601,
      source: user_event.source,
      environment: Rails.env,
      user: user_payload(user),
      segments: user.user_segments.active.order(:segment_name).pluck(:segment_name),
      subscription: subscription_payload(user.subscription, user),
      engagement: engagement_payload(user),
      metadata: RelationshipEventTracker.sanitize_metadata(user_event.metadata || {})
    }
  end

  def user_payload(user)
    payload = { id: user.id }
    return payload if MakeWebhookEligibility.payload_mode == "minimal"

    payload.merge(
      email: user.email,
      name: user.name,
      locale: "pt-BR"
    )
  end

  def subscription_payload(subscription, user)
    {
      status: subscription&.status || "none",
      trial_ends_at: subscription&.trial_end&.iso8601 || user.trial_ends_at&.iso8601,
      plan: subscription&.plan_name || "none"
    }
  end

  def engagement_payload(user)
    last_workout_at = user.workout_sessions.maximum(:completed_at)
    {
      created_at: user.created_at.iso8601,
      last_sign_in_at: nil,
      last_workout_at: last_workout_at&.iso8601,
      total_workouts_created: user.workout_plans.count,
      total_workouts_completed: user.workout_sessions.count,
      days_since_last_workout: last_workout_at ? (Date.current - last_workout_at.to_date).to_i : nil
    }
  end

  def mark_failed(user_event, error)
    user_event.update!(
      make_delivery_status: "failed",
      make_last_error: error.to_s.first(1000)
    )
    Result.new(status: "failed", error: error)
  end
end
