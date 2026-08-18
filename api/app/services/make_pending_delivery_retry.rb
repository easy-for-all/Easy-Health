class MakePendingDeliveryRetry
  STALE_SENDING_AFTER = 5.minutes
  RECOVERED_SENDING_RETRY_DELAY = 1.minute
  ABANDONED_SENDING_ERROR = "abandoned_sending_attempt".freeze

  def self.call(scope:, batch: true)
    new(scope:, batch:).call
  end

  def self.retriable_scope(pending_scope:, now: Time.current, stale_sending_before: now - STALE_SENDING_AFTER)
    due_retrying = UserEvent.where(make_delivery_status: "retrying").where(make_next_retry_at: ..now)
    stale_sending = UserEvent.where(make_delivery_status: "sending").where(make_last_attempt_at: ..stale_sending_before)

    pending_scope.or(due_retrying).or(stale_sending)
  end

  def self.terminal_relationship_messages
    RelationshipMessage.where(status: RelationshipMessage::TERMINAL_STATUSES).where.not(user_event_id: nil)
  end

  def self.terminal_relationship_user_event_ids
    terminal_relationship_messages.select(:user_event_id)
  end

  def self.terminal_relationship_message_for(user_event)
    terminal_relationship_messages
      .where(user_event_id: user_event.id)
      .order(updated_at: :desc, id: :desc)
      .first
  end

  def initialize(scope:, batch:)
    @scope = scope
    @batch = batch
  end

  def call
    stats = {
      considered: 0,
      delivered: 0,
      failed: 0,
      recovered_sending: 0,
      reconciled_terminal: 0,
      already_claimed: 0
    }

    each_event do |event, terminal_message|
      stats[:considered] += 1

      case prepare_event(event, terminal_message)
      when :reconciled_terminal
        stats[:reconciled_terminal] += 1
        next
      when :already_claimed
        stats[:already_claimed] += 1
        next
      when :recovered_sending
        stats[:recovered_sending] += 1
      end

      result = MakeWebhookClient.new.deliver(event)
      result.success? ? stats[:delivered] += 1 : stats[:failed] += 1
    rescue StandardError
      stats[:failed] += 1
    end

    stats
  end

  private

  attr_reader :scope, :batch

  def each_event(&block)
    if batch
      scope.find_in_batches do |events|
        terminal_messages = terminal_messages_by_event_id(events)
        events.each { |event| yield(event, terminal_messages[event.id]) }
      end
    else
      events = scope.to_a
      terminal_messages = terminal_messages_by_event_id(events)
      events.each { |event| yield(event, terminal_messages[event.id]) }
    end
  end

  def terminal_messages_by_event_id(events)
    ids = events.map(&:id)
    return {} if ids.empty?

    self.class.terminal_relationship_messages
        .where(user_event_id: ids)
        .order(updated_at: :desc, id: :desc)
        .each_with_object({}) do |message, indexed|
          indexed[message.user_event_id] ||= message
        end
  end

  def prepare_event(event, terminal_message)
    if terminal_message
      reconcile_terminal(event, terminal_message)
      return :reconciled_terminal
    end

    return :deliver unless event.make_delivery_status == "sending"

    recover_stale_sending(event)
  end

  def recover_stale_sending(event)
    return :deliver unless event.make_delivery_status == "sending"

    now = Time.current
    updated = UserEvent
              .where(id: event.id, make_delivery_status: "sending")
              .where.not(id: self.class.terminal_relationship_user_event_ids)
              .update_all( # rubocop:disable Rails/SkipsModelValidations
                updated_at: now,
                make_delivery_status: "retrying",
                make_last_error: ABANDONED_SENDING_ERROR,
                make_last_error_class: nil,
                make_last_error_message: "Attempt abandoned before final Make delivery status was persisted",
                make_delivery_duration_ms: abandoned_duration_ms(event, now),
                make_next_retry_at: now + RECOVERED_SENDING_RETRY_DELAY
              )

    if updated == 1
      event.reload
      return :recovered_sending
    end

    terminal_message = terminal_relationship_message_for(event)
    if terminal_message
      reconcile_terminal(event, terminal_message)
      return :reconciled_terminal
    end

    :already_claimed
  end

  def reconcile_terminal(event, terminal_message)
    Make::UserEventReconciler.from_relationship_message(terminal_message, user_event: event)
  end

  def terminal_relationship_message_for(event)
    self.class.terminal_relationship_message_for(event)
  end

  def abandoned_duration_ms(event, now = Time.current)
    return nil unless event.make_last_attempt_at

    ((now - event.make_last_attempt_at) * 1000).round
  end
end
