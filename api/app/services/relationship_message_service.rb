class RelationshipMessageService
  Result = Struct.new(:success, :record, :error, keyword_init: true) do
    def success? = success
  end

  # Mirrors the pattern from RelationshipEventTracker
  SENSITIVE_KEY_PATTERN = /password|token|secret|authorization|card|stripe|cpf|ssn|cvv|cvc|dsn|api_key|access_key/i

  TRACKING_STATUSES = %w[delivered opened clicked].freeze

  def self.record_from_make!(payload:, headers: {})
    new(payload: payload).record!
  end

  def initialize(payload:)
    @payload = payload.with_indifferent_access
  end

  def record!
    user = find_user
    return Result.new(success: false, error: "user_not_found") unless user

    status = @payload[:status].to_s
    return Result.new(success: false, error: "invalid_status") unless RelationshipMessage::STATUSES.include?(status)

    return Result.new(success: false, error: "missing_channel")   unless RelationshipMessage::CHANNELS.include?(@payload[:channel].to_s)
    return Result.new(success: false, error: "missing_provider")  unless RelationshipMessage::PROVIDERS.include?(@payload[:provider].to_s)
    return Result.new(success: false, error: "missing_event_name") if @payload[:event_name].blank?

    message = find_or_build_message(user, status)
    assign_attributes(message, user, status)

    if message.save
      Result.new(success: true, record: message)
    else
      Result.new(success: false, error: message.errors.full_messages.join(", "))
    end
  rescue => e
    Rails.logger.error("[RelationshipMessageService] #{e.class}: #{e.message}")
    Result.new(success: false, error: "internal_error")
  end

  private

  def find_user
    User.find_by(id: @payload[:user_id])
  end

  def find_user_event(user)
    return nil if @payload[:user_event_id].blank?
    UserEvent.find_by(id: @payload[:user_event_id], user: user)
  end

  def find_or_build_message(user, status)
    idempotency_key = build_idempotency_key

    if idempotency_key.present?
      return RelationshipMessage.find_or_initialize_by(idempotency_key: idempotency_key)
    end

    # For tracking events (delivered/opened/clicked), try to match existing record
    if TRACKING_STATUSES.include?(status) && @payload[:provider_message_id].present?
      existing = RelationshipMessage.find_by(
        provider_message_id: @payload[:provider_message_id],
        user_id: user.id
      )
      return existing if existing
    end

    RelationshipMessage.new
  end

  def build_idempotency_key
    metadata   = @payload[:metadata] || {}
    exec_id    = metadata[:make_execution_id].presence
    return nil if exec_id.blank?

    "make:#{exec_id}:#{@payload[:step_key]}:#{@payload[:user_id]}"
  end

  def assign_attributes(message, user, status)
    user_event = find_user_event(user)

    message.assign_attributes(
      user:                  user,
      user_event:            user_event,
      event_name:            @payload[:event_name],
      journey_key:           @payload[:journey_key],
      step_key:              @payload[:step_key],
      channel:               @payload[:channel],
      provider:              @payload[:provider],
      template_key:          @payload[:template_key],
      subject:               @payload[:subject],
      recipient_email:       @payload[:recipient_email],
      status:                status,
      provider_message_id:   @payload[:provider_message_id],
      provider_response_json: sanitize_metadata(@payload[:provider_response] || {}),
      error_message:         @payload[:error_message],
      metadata_json:         sanitize_metadata(@payload[:metadata] || {})
    )

    apply_timestamps(message, status)
  end

  def apply_timestamps(message, status)
    case status
    when "sent"
      message.sent_at ||= parse_time(@payload[:sent_at]) || Time.current
    when "failed"
      message.failed_at ||= Time.current
    when "skipped"
      message.skipped_at ||= Time.current
    end
  end

  def parse_time(value)
    return nil if value.blank?
    Time.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def sanitize_metadata(metadata)
    return {} unless metadata.is_a?(Hash)
    metadata.each_with_object({}) do |(k, v), result|
      next if k.to_s.match?(SENSITIVE_KEY_PATTERN)
      result[k] = v.is_a?(Hash) ? sanitize_metadata(v) : v
    end
  end
end
