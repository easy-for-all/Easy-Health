# Shared logic for the activation reminder jobs (2h/24h). Subclasses only
# define the event name and lookback window; the candidate/idempotency logic
# is identical. Fires RelationshipEventTracker events that are NOT (yet)
# included in MAKE_WEBHOOK_ALLOWED_EVENTS, so nothing is actually sent to
# Make until that's turned on explicitly via config.
class ActivationReminderJob < ApplicationJob
  queue_as :default

  def perform
    stats = { candidates_found: 0, events_created: 0 }

    candidate_events.find_each do |activation_event|
      user = activation_event.user
      next unless user
      next if user.workout_sessions.exists?
      next if first_workout_started?(user)

      stats[:candidates_found] += 1
      key = idempotency_key(user, activation_event)
      next if UserEvent.exists?(user: user, event_name: event_name, idempotency_key: key)

      event = RelationshipEventTracker.track(
        user: user,
        event_name: event_name,
        metadata: {
          workout_plan_id: activation_event.metadata["workout_plan_id"],
          activation_event_id: activation_event.id
        },
        occurred_at: Time.current,
        idempotency_key: key,
        source: "activation_reminder"
      )
      stats[:events_created] += 1 if event
    end

    Rails.logger.info("[#{self.class.name}] #{stats.inspect}")
    stats
  end

  private

  def candidate_events
    UserEvent.where(event_name: "activation_workout_created", created_at: window_range)
  end

  def first_workout_started?(user)
    UserEvent.exists?(user: user, event_name: "first_workout_started")
  end

  def idempotency_key(user, activation_event)
    "#{event_name}:#{user.id}:#{activation_event.id}"
  end

  def event_name
    raise NotImplementedError, "#{self.class} must implement #event_name"
  end

  def window_range
    raise NotImplementedError, "#{self.class} must implement #window_range"
  end
end
