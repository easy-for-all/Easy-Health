module PushNotifications
  # Single technical send path shared by the internal activation scheduler
  # (PushDispatchService) and the Make-orchestrated endpoint
  # (Make::PushDispatchRequest).
  #
  # Responsibilities: resolve the user's ACTIVE device tokens, send one FCM
  # message per token via FirebasePushService, stop at the first accepted token,
  # invalidate ONLY definitively-dead tokens, and never repeat an already-accepted
  # token. It does NOT decide eligibility/opt-out (callers do) and it never logs a
  # raw token.
  #
  # Callers own domain tracking (user_events): this class returns per-device
  # outcomes so each caller can record provider accept/reject with its own
  # metadata (variant, delivery_id, dispatch_id, ...).
  class FcmDispatcher
    Outcome = Struct.new(:device, :result, keyword_init: true)

    Result = Struct.new(
      :tokens_attempted, :tokens_accepted, :tokens_rejected,
      :provider_message_id, :last_error_code, :last_error_message, :outcomes,
      keyword_init: true
    ) do
      def sent?
        tokens_accepted.to_i.positive?
      end

      def partial?
        sent? && tokens_rejected.to_i.positive?
      end

      def accepted_device
        outcomes.find { |o| o.result.sent? }&.device
      end
    end

    def initialize(firebase: FirebasePushService.new)
      @firebase = firebase
    end

    def call(user:, title:, body:, data: {}, notification_type: nil, correlation_id: nil)
      devices = user.device_tokens.active.to_a
      outcomes = []
      accepted = 0
      rejected = 0
      message_id = nil
      last_error = nil
      last_message = nil

      devices.each do |device|
        result = @firebase.deliver(token: device.token, title:, body:, data:)
        outcomes << Outcome.new(device:, result:)

        # Definitive-only invalidation (UNREGISTERED / SENDER_ID_MISMATCH / 404).
        # Ambiguous (INVALID_ARGUMENT) and temporary (timeout / 429 / 5xx) failures
        # leave the token enabled.
        device.invalidate!(result.error_code) if result.invalid_token

        if result.sent?
          accepted += 1
          message_id ||= result.message_id
          break # one accepted device is enough; don't spam the user's others
        else
          rejected += 1
          last_error = result.error_code
          last_message = result.error_message
          log_failure(device, result, correlation_id)
        end
      end

      Result.new(
        tokens_attempted: outcomes.size,
        tokens_accepted: accepted,
        tokens_rejected: rejected,
        provider_message_id: message_id,
        last_error_code: last_error,
        last_error_message: last_message,
        outcomes: outcomes
      )
    end

    private

    def log_failure(device, result, correlation_id)
      Rails.logger.info(
        "[FcmDispatcher] send failed corr=#{correlation_id} " \
        "device=#{device.masked_token} error=#{result.error_code} #{result.error_message}"
      )
    end
  end
end
