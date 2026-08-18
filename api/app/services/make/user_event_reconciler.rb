module Make
  class UserEventReconciler
    MAKE_RECEIVED_STATUSES = %w[received routed filtered completed failed sent skipped].freeze

    def self.call(user_event:, status:, message: nil, execution_id: nil, callback_at: Time.current)
      new(user_event:, status:, message:, execution_id:, callback_at:).call
    end

    def self.from_relationship_message(relationship_message, user_event: relationship_message.user_event)
      return false unless relationship_message
      return false unless RelationshipMessage::TERMINAL_STATUSES.include?(relationship_message.status)

      call(
        user_event: user_event,
        status: relationship_message.status,
        message: relationship_message.error_message,
        execution_id: relationship_message.metadata_json["make_execution_id"],
        callback_at: terminal_timestamp(relationship_message)
      )
    end

    def self.terminal_timestamp(relationship_message)
      case relationship_message.status
      when "sent"
        relationship_message.sent_at
      when "failed"
        relationship_message.failed_at
      when "skipped"
        relationship_message.skipped_at
      end || relationship_message.updated_at || Time.current
    end

    def initialize(user_event:, status:, message:, execution_id:, callback_at:)
      @user_event = user_event
      @status = status.to_s
      @message = message
      @execution_id = execution_id
      @callback_at = callback_at || Time.current
    end

    def call
      return false unless user_event
      return false unless UserEvent::PROCESSING_STATUSES.include?(status)

      user_event.with_lock do
        user_event.reload
        user_event.update!(attributes_for_update)
      end
      true
    end

    private

    attr_reader :user_event, :status, :message, :execution_id, :callback_at

    def attributes_for_update
      attrs = {
        make_processing_status: status,
        make_callback_at: callback_at
      }
      attrs[:make_processing_message] = message if message.present?
      attrs[:make_execution_id] = execution_id if execution_id.present?

      if received_by_make?
        attrs[:make_delivery_status] = "accepted_by_make"
        attrs[:make_delivered_to_provider_at] = user_event.make_delivered_to_provider_at || callback_at
        attrs[:make_next_retry_at] = nil
      end

      attrs
    end

    def received_by_make?
      MAKE_RECEIVED_STATUSES.include?(status) &&
        UserEvent::ACTIVE_DELIVERY_STATUSES.include?(user_event.make_delivery_status)
    end
  end
end
