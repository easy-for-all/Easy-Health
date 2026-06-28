class RelationshipBackfillJob < ApplicationJob
  queue_as :default

  def perform(dry_run: true, allow_make_delivery: false)
    dry_run = ActiveModel::Type::Boolean.new.cast(dry_run)
    allow_make_delivery = ActiveModel::Type::Boolean.new.cast(allow_make_delivery)
    stats = {
      dry_run: dry_run,
      allow_make_delivery: allow_make_delivery,
      users_processed: 0,
      segment_changes: 0,
      events_created: 0,
      make_eligible_events: 0,
      make_delivery_suppressed_events: 0
    }

    eligible_users.find_each do |user|
      stats[:users_processed] += 1
      stats[:segment_changes] += UserSegmentCalculator.call(user, dry_run: dry_run).segment_changes

      backfill_event_candidates(user).each do |candidate|
        next if event_exists?(user, candidate)

        make_eligible = MakeWebhookEligibility.eligible_for_new_event?(
          user: user,
          event_name: candidate[:event_name],
          suppress_make_delivery: false
        )
        stats[:make_eligible_events] += 1 if make_eligible
        stats[:make_delivery_suppressed_events] += 1 if make_eligible && !allow_make_delivery

        if dry_run
          stats[:events_created] += 1
          next
        end

        event = RelationshipEventTracker.track(
          user: user,
          event_name: candidate[:event_name],
          metadata: candidate[:metadata].merge(
            retroactive: true,
            allow_make_delivery: allow_make_delivery
          ),
          occurred_at: candidate[:occurred_at],
          idempotency_key: candidate[:idempotency_key],
          source: "relationship_backfill",
          suppress_make_delivery: !allow_make_delivery
        )
        stats[:events_created] += 1 if event
      end
    end

    message = "[RelationshipBackfillJob] #{stats.inspect}"
    Rails.logger.info(message)
    puts message
    stats
  end

  private

  def eligible_users
    User.where(deletion_requested_at: nil, anonymized_at: nil)
  end

  def backfill_event_candidates(user)
    candidates = []
    candidates << user_created_candidate(user)
    candidates << trial_started_candidate(user)
    candidates.concat(trial_expiration_candidates(user))
    candidates << subscription_created_candidate(user)
    candidates.concat(workout_plan_candidates(user))
    candidates << first_workout_completed_candidate(user)
    candidates << partial_recently_candidate(user)
    candidates << body_photo_candidate(user)
    candidates << plan_created_but_not_used_candidate(user)
    candidates.concat(inactivity_candidates(user))
    candidates.compact
  end

  def user_created_candidate(user)
    {
      event_name: "user_created",
      occurred_at: user.created_at,
      idempotency_key: "user_created:#{user.id}",
      metadata: { backfilled_from_user_created_at: user.created_at.iso8601 }
    }
  end

  def trial_started_candidate(user)
    return unless user.trial_started_at.present?

    {
      event_name: "trial_started",
      occurred_at: user.trial_started_at,
      idempotency_key: "trial_started:#{user.id}:#{user.trial_started_at.to_date}",
      metadata: { trial_started_at: user.trial_started_at.iso8601, trial_ends_at: user.trial_ends_at&.iso8601 }
    }
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
        occurred_at: user.trial_ends_at,
        idempotency_key: "trial_expired_without_subscription:#{user.id}:#{trial_date}",
        metadata: { trial_ends_at: user.trial_ends_at.iso8601 }
      }
    ]
  end

  def subscription_created_candidate(user)
    sub = user.subscription
    return unless sub&.status&.in?(%w[active trialing])

    {
      event_name: "subscription_created",
      occurred_at: sub.created_at,
      idempotency_key: "subscription_created:#{user.id}:#{sub.id}",
      metadata: { subscription_id: sub.id, status: sub.status, plan_name: sub.plan_name }
    }
  end

  def workout_plan_candidates(user)
    first_plan = user.workout_plans.order(:created_at).first
    return [] unless first_plan

    [
      {
        event_name: "workout_created",
        occurred_at: first_plan.created_at,
        idempotency_key: "workout_created:#{user.id}:#{first_plan.id}",
        metadata: { workout_plan_id: first_plan.id }
      },
      {
        event_name: "first_workout_created",
        occurred_at: first_plan.created_at,
        idempotency_key: "first_workout_created:#{user.id}:#{first_plan.id}",
        metadata: { workout_plan_id: first_plan.id }
      }
    ]
  end

  def first_workout_completed_candidate(user)
    first_session = user.workout_sessions.order(:completed_at).first
    return unless first_session

    {
      event_name: "first_workout_completed",
      occurred_at: first_session.completed_at,
      idempotency_key: "first_workout_completed:#{user.id}:#{first_session.id}",
      metadata: { workout_session_id: first_session.id, duration_minutes: first_session.duration_minutes }
    }
  end

  def partial_recently_candidate(user)
    session = user.workout_sessions
                  .where(completion_status: "completed_partial")
                  .where(completed_at: 7.days.ago..)
                  .order(completed_at: :desc)
                  .first
    return unless session

    {
      event_name: "workout_completed_partial",
      occurred_at: session.completed_at,
      idempotency_key: "workout_completed_partial:#{user.id}:#{session.id}",
      metadata: {
        workout_session_id: session.id,
        completion_rate: session.completion_rate,
        completed_sets_count: session.completed_sets_count,
        planned_sets_count: session.planned_sets_count
      }
    }
  end

  def body_photo_candidate(user)
    media = user.user_media.where(category: "body_photo").order(:created_at).first
    return unless media

    {
      event_name: "body_photo_uploaded",
      occurred_at: media.created_at,
      idempotency_key: "body_photo_uploaded:#{user.id}:#{media.id}",
      metadata: { media_id: media.id }
    }
  end

  def plan_created_but_not_used_candidate(user)
    first_plan = user.workout_plans.order(:created_at).first
    return unless first_plan
    return if user.workout_sessions.exists?

    {
      event_name: "plan_created_but_not_used",
      occurred_at: first_plan.created_at,
      idempotency_key: "plan_created_but_not_used:#{user.id}:#{first_plan.id}",
      metadata: { workout_plan_id: first_plan.id, workout_plan_created_at: first_plan.created_at.iso8601 }
    }
  end

  def inactivity_candidates(user)
    last_workout_at = user.workout_sessions.maximum(:completed_at)
    return [] unless last_workout_at

    days_inactive = (Date.current - last_workout_at.to_date).to_i
    [3, 7, 15].filter_map do |threshold|
      next unless days_inactive >= threshold

      event_name = "user_inactive_#{threshold}_days"
      {
        event_name: event_name,
        occurred_at: last_workout_at + threshold.days,
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
