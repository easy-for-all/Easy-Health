require "digest"
require "securerandom"

# Sends the single, clearly-labelled "admin push test" message to the CURRENT
# admin user's own active device tokens. Reused by both the authenticated
# endpoint (Api::V1::AdminController#push_test) and the rake task
# (push:test:send_now) so the two share identical guards and payload.
#
# Safety invariants:
# - Only an admin user may trigger it (caller must pass the admin; we re-check).
# - It ONLY ever targets the given user's own tokens — no user_id is accepted
#   from the outside, the caller passes a resolved User.
# - Per-user cooldown rate limit via Rails.cache.
# - Every attempt is audited (admin_push_test_requested) with a correlation_id.
# - Tokens are never returned/logged raw (masked / SHA digest only).
class AdminPushTestService
  TITLE = "Teste EasyHealth".freeze
  BODY = "Sua configuração de notificações está funcionando.".freeze
  TYPE = "admin_push_test".freeze
  # A safe, allow-listed deep-link target (see web push-deep-link allowlist).
  TARGET_PATH = "/workouts/ready".freeze
  COOLDOWN = 30.seconds

  Result = Struct.new(:ok, :error, :correlation_id, :devices, keyword_init: true) do
    def ok? = ok == true
  end
  DeviceResult = Struct.new(:masked_token, :status, :message_id, :error_code, :invalidated, keyword_init: true)

  def initialize(user)
    @user = user
  end

  # correlation_id lets us tie the request → provider events → on-device logs.
  def call(correlation_id: SecureRandom.uuid)
    return failure("not_admin", correlation_id) unless @user&.admin?
    return failure("rate_limited", correlation_id) if rate_limited?
    return failure("not_configured", correlation_id) unless FirebasePushService.configured?

    devices = @user.device_tokens.active.to_a
    return failure("no_active_device", correlation_id) if devices.empty?

    stamp_rate_limit!
    service = FirebasePushService.new
    device_results = devices.map { |device| deliver_one(service, device, correlation_id) }
    audit(correlation_id, device_results)

    Result.new(
      ok: device_results.any? { |r| r.status == "sent" },
      error: nil,
      correlation_id: correlation_id,
      devices: device_results
    )
  end

  private

  def failure(error, correlation_id)
    Result.new(ok: false, error: error, correlation_id: correlation_id, devices: [])
  end

  def deliver_one(service, device, correlation_id)
    result = service.deliver(
      token: device.token,
      title: TITLE,
      body: BODY,
      data: { type: TYPE, target_path: TARGET_PATH, correlation_id: correlation_id, test: "1" }
    )
    track_provider(result, device, correlation_id)

    invalidated = false
    if result.invalid_token
      device.invalidate!(result.error_code || "admin_push_test_invalid")
      invalidated = true
    end

    DeviceResult.new(
      masked_token: device.masked_token,
      status: result.status,
      message_id: result.message_id,
      error_code: result.error_code,
      invalidated: invalidated
    )
  end

  # Distinguishes "FCM accepted the message" from "FCM rejected it" — never
  # asserts on-device delivery (that is only proven by an app-side event).
  def track_provider(result, device, correlation_id)
    UserEventService.track(
      user: @user,
      event_name: result.sent? ? "push_provider_accepted" : "push_provider_rejected",
      metadata: {
        notification_type: TYPE,
        platform: "android",
        correlation_id: correlation_id,
        provider_message_id: result.message_id,
        error_code: result.error_code,
        device_digest: device_digest(device.token)
      },
      source: "activation_push",
      suppress_make_delivery: true
    )
  end

  def audit(correlation_id, device_results)
    UserEventService.track(
      user: @user,
      event_name: "admin_push_test_requested",
      metadata: {
        correlation_id: correlation_id,
        platform: "android",
        device_count: device_results.size,
        statuses: device_results.map(&:status),
        environment: Rails.env
      },
      source: "activation_push",
      suppress_make_delivery: true
    )
  end

  def rate_limited?
    Rails.cache.read(cache_key).present?
  end

  def stamp_rate_limit!
    Rails.cache.write(cache_key, Time.current.to_i, expires_in: COOLDOWN)
  end

  def cache_key
    "admin_push_test:#{@user.id}"
  end

  # A short, non-reversible fingerprint — safe for logs/metrics. Deliberately
  # NOT named with "token" so the event sanitizer never strips it.
  def device_digest(token)
    return nil if token.blank?

    Digest::SHA256.hexdigest(token)[0, 12]
  end
end
