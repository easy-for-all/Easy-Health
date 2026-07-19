class RelationshipDailyJob < ApplicationJob
  queue_as :default

  def perform
    stats = { users_processed: 0, segment_changes: 0, events_created: 0 }

    eligible_users.find_each do |user|
      stats[:users_processed] += 1
      stats[:segment_changes] += UserSegmentCalculator.call(user).segment_changes

      daily_event_candidates(user).each do |candidate|
        next if event_exists?(user, candidate)

        event = RelationshipEventTracker.track(
          user: user,
          event_name: candidate[:event_name],
          metadata: candidate[:metadata],
          occurred_at: candidate[:occurred_at],
          idempotency_key: candidate[:idempotency_key],
          source: "relationship_daily"
        )
        next unless event

        stats[:events_created] += 1
        # Funnel: mark push-routed events (e.g. user_inactive_3/7_days) eligible.
        if CommunicationEvents.supports_channel?(candidate[:event_name], "push")
          PushJourney.track_eligible(user: user, event_name: candidate[:event_name],
                                     metadata: { campaign_key: candidate[:event_name] })
        end
      end
    end

    Rails.logger.info("[RelationshipDailyJob] #{stats.inspect}")
    stats
  end

  private

  def eligible_users
    User.where(deletion_requested_at: nil, anonymized_at: nil)
  end

  def daily_event_candidates(user)
    candidates = []
    candidates.concat(trial_day_candidates(user))
    candidates.concat(trial_expiration_candidates(user))
    candidates << plan_created_but_not_used_candidate(user)
    candidates.concat(inactivity_candidates(user))
    candidates.compact
  end

  def trial_day_candidates(user)
    return [] unless user.trial_started_at.present?
    return [] if subscriber_active?(user)

    days_since_trial_start = (Date.current - user.trial_started_at.to_date).to_i
    return [] unless [ 1, 3, 6 ].include?(days_since_trial_start)

    event_name = "trial_day_#{days_since_trial_start}"
    [ {
      event_name: event_name,
      occurred_at: Time.current,
      idempotency_key: "#{event_name}:#{user.id}:#{user.trial_started_at.to_date}",
      metadata: { days_since_trial_start: days_since_trial_start }
    } ]
  end

  def trial_expiration_candidates(user)
    return [] unless user.trial_expired?
    return [] if subscriber_active?(user)

    trial_date = user.trial_ends_at.to_date
    [
      {
        event_name: "trial_expired",
        occurred_at: user.trial_ends_at,
        idempotency_key: "trial_expired:#{user.id}:#{trial_date}",
        metadata: { trial_ends_at: user.trial_ends_at.iso8601 }
      },
      {
        event_name: "trial_expired_without_subscription",
        occurred_at: Time.current,
        idempotency_key: "trial_expired_without_subscription:#{user.id}:#{trial_date}",
        metadata: { trial_ends_at: user.trial_ends_at.iso8601 }
      }
    ]
  end

  def plan_created_but_not_used_candidate(user)
    first_plan = user.workout_plans.order(:created_at).first
    return unless first_plan
    return if user.workout_sessions.exists?
    return if first_plan.created_at > 24.hours.ago

    {
      event_name: "plan_created_but_not_used",
      occurred_at: Time.current,
      idempotency_key: "plan_created_but_not_used:#{user.id}:#{first_plan.id}",
      metadata: { workout_plan_id: first_plan.id, workout_plan_created_at: first_plan.created_at.iso8601 }
    }
  end

  def inactivity_candidates(user)
    last_workout_at = user.workout_sessions.maximum(:completed_at)
    return [] unless last_workout_at
    # Inactivity events route to push; respect the quiet-hours window (V1).
    return [] unless PushQuietHours.allowed?(user: user)

    days_inactive = (Date.current - last_workout_at.to_date).to_i
    [ 3, 7 ].filter_map do |threshold|
      next unless days_inactive >= threshold

      event_name = "user_inactive_#{threshold}_days"
      {
        event_name: event_name,
        occurred_at: Time.current,
        idempotency_key: "#{event_name}:#{user.id}:#{last_workout_at.to_date}",
        metadata: { days_since_last_workout: days_inactive, last_workout_at: last_workout_at.iso8601 }
      }
    end
  end

  def subscriber_active?(user)
    user.subscription&.status&.in?(%w[active trialing])
  end

  def event_exists?(user, candidate)
    UserEvent.exists?(
      user: user,
      event_name: candidate[:event_name],
      idempotency_key: candidate[:idempotency_key]
    )
  end
end
