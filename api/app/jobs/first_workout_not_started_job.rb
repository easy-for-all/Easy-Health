# Shared logic for the "first workout not started" reminders (2h / 24h).
# Detects eligibility, re-checks the LIVE condition, and emits the business
# event exactly once. The event is delivered to Make, which selects the copy and
# calls the push dispatch endpoint.
#
# Quiet hours are deliberately NOT consulted here. "This user created a plan 2h
# ago and never started it" is a fact regardless of the local clock; whether a
# push may be sent for it is decided later, at dispatch.
#
# Cancellation is implicit: if the user starts a workout the condition fails and
# no event is emitted. Idempotency (per anchor event) prevents duplicates.
#
# Subclasses only define #event_name and #window_range. Anchor =
# activation_workout_created (emitted once when the first plan is created).
class FirstWorkoutNotStartedJob < ApplicationJob
  queue_as :default

  def perform
    stats = { candidates_found: 0, events_created: 0, already_emitted: 0 }

    candidate_events.find_each do |anchor_event|
      user = anchor_event.user
      next unless user
      next if started_first_workout?(user)

      stats[:candidates_found] += 1

      key = idempotency_key(user, anchor_event)
      if UserEvent.exists?(user: user, event_name: event_name, idempotency_key: key)
        stats[:already_emitted] += 1
        next
      end

      event = emit(user, anchor_event, key)
      stats[:events_created] += 1 if event
    end

    @heartbeat_metadata = stats
    Rails.logger.info("[#{self.class.name}] #{stats.inspect}")
    stats
  end

  # Reported on the heartbeat so the admin can tell "ran and found nothing" from
  # "ran and produced nothing", which look identical from liveness alone.
  attr_reader :heartbeat_metadata

  private

  def candidate_events
    UserEvent.where(event_name: "activation_workout_created", created_at: window_range)
  end

  # "Started" = any workout session OR the first_workout_started event.
  def started_first_workout?(user)
    user.workout_sessions.exists? ||
      UserEvent.exists?(user: user, event_name: "first_workout_started")
  end

  def emit(user, anchor_event, key)
    event = RelationshipEventTracker.track(
      user: user,
      event_name: event_name,
      metadata: {
        workout_plan_id: anchor_event.metadata["workout_plan_id"],
        activation_event_id: anchor_event.id,
        # The journey's origin, kept apart from origin_surface: THIS event was
        # produced by the scheduler, but it started from wherever the user
        # created the plan. Two questions, two fields, no second column.
        anchor_event_id: anchor_event.id,
        anchor_origin_surface: anchor_event.origin_surface.presence || "unknown",
        first_workout_created_at: anchor_event.created_at.iso8601
      },
      occurred_at: Time.current,
      idempotency_key: key,
      source: "push_journey",
      origin_surface: "backend_scheduler"
    )
    # Funnel: eligible fires on successful creation; requested_to_make is emitted
    # centrally by MakeWebhookClient when the webhook is actually delivered.
    PushJourney.track_eligible(user: user, event_name: event_name, metadata: eligible_metadata(anchor_event)) if event
    event
  end

  def eligible_metadata(anchor_event)
    {
      campaign_key: event_name,
      hours_since_event: ((Time.current - anchor_event.created_at) / 3600).floor
    }
  end

  def idempotency_key(user, anchor_event)
    "#{event_name}:#{user.id}:#{anchor_event.id}"
  end

  def event_name
    raise NotImplementedError, "#{self.class} must implement #event_name"
  end

  def window_range
    raise NotImplementedError, "#{self.class} must implement #window_range"
  end
end
