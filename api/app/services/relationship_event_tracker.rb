class RelationshipEventTracker
  EVENTS = %w[
    user_created
    signup_completed
    trial_started
    trial_day_1
    trial_day_3
    trial_day_6
    trial_expired
    subscription_created
    subscription_renewed
    subscription_canceled
    workout_created
    first_workout_created
    workout_started
    first_workout_started
    workout_completed
    first_workout_completed
    workout_completed_partial
    workout_abandoned
    user_inactive_3_days
    user_inactive_7_days
    user_inactive_15_days
    body_photo_uploaded
    body_photo_deleted
    streak_3
    streak_7
    streak_lost
    personal_record
    plan_created_but_not_used
    trial_expired_without_subscription
    never_created_workout
    workout_created_not_started
    high_intent_trial
    churn_risk
    onboarding_completed
    fitness_profile_created
    fitness_profile_recalculated
    persona_classified
    training_archetype_classified
    behavior_pattern_updated
    progress_viewed
    favorite_added
    photo_uploaded
    exam_uploaded
    bioimpedance_added
    paywall_viewed
    checkout_started
    workout_strategy_created
    ai_workout_generated
    ai_workout_validation_failed
    coach_insight_created
    exercise_favorited
    exercise_skipped
    exercise_substituted
    ai_workout_chat_started
    ai_workout_message_sent
    ai_workout_blocked_security
    ai_workout_blocked_out_of_scope
    ai_workout_preview_generated
    ai_workout_preview_adjusted
    ai_workout_confirmed
    ai_workout_creation_failed
    activation_workout_created
    activation_first_workout_completed
    activation_reminder_2h_due
    activation_reminder_24h_due
    push_scheduled
    push_sent
    push_failed
    push_opened
    push_deep_link_opened
    push_provider_accepted
    push_provider_rejected
    admin_push_test_requested
    push_frequency_bypass_granted
    push_frequency_bypass_denied
    workout_started_from_push
    workout_completed_from_push
    first_workout_not_started_2h
    first_workout_not_started_24h
    push_event_eligible
    push_requested_to_make
    push_dispatch_skipped
    notification_disliked
    notification_type_disabled
    notification_time_changed
    notification_skipped
  ].uniq.freeze

  SENSITIVE_KEY_PATTERN = /(password|token|secret|authorization|card|stripe|cpf|ssn|cvv|cvc|dsn|api_key|access_key)/i

  def self.track(user:, event_name: nil, event: nil, metadata: {}, source: "easyhealth_backend",
                 occurred_at: Time.current, idempotency_key: nil, suppress_make_delivery: false)
    new(
      user: user,
      event_name: event_name || event,
      metadata: metadata,
      source: source,
      occurred_at: occurred_at,
      idempotency_key: idempotency_key,
      suppress_make_delivery: suppress_make_delivery
    ).track
  end

  def self.sanitize_metadata(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, child), result|
        next if key.to_s.match?(SENSITIVE_KEY_PATTERN)

        result[key.to_s] = sanitize_metadata(child)
      end
    when Array
      value.map { |child| sanitize_metadata(child) }
    when Time, ActiveSupport::TimeWithZone, DateTime
      value.iso8601
    when Date
      value.iso8601
    else
      value
    end
  end

  def initialize(user:, event_name:, metadata:, source:, occurred_at:, idempotency_key:, suppress_make_delivery:)
    @user = user
    @event_name = event_name.to_s
    @metadata = self.class.sanitize_metadata(metadata || {})
    @source = source.to_s.presence || "easyhealth_backend"
    @occurred_at = occurred_at || Time.current
    @idempotency_key = idempotency_key.presence
    @suppress_make_delivery = suppress_make_delivery
  end

  def track
    return unless valid_event?

    user_event = persist_event
    enqueue_make_delivery(user_event) if user_event&.make_delivery_status == "pending"
    user_event
  rescue ActiveRecord::RecordNotUnique
    find_existing_event
  rescue => e
    Rails.logger.warn("[RelationshipEventTracker] Failed to track #{@event_name} for user #{@user&.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  def valid_event?
    return false unless @user
    return true if EVENTS.include?(@event_name)

    Rails.logger.warn("[RelationshipEventTracker] Ignoring unknown event #{@event_name.inspect} for user #{@user.id}")
    false
  end

  def persist_event
    attrs = event_attributes

    if @idempotency_key
      user_event = UserEvent.find_or_initialize_by(
        user: @user,
        event_name: @event_name,
        idempotency_key: @idempotency_key
      )
      return user_event if user_event.persisted?

      user_event.assign_attributes(attrs)
      user_event.save!
      user_event
    else
      UserEvent.create!(attrs)
    end
  end

  def find_existing_event
    return unless @idempotency_key

    UserEvent.find_by(user: @user, event_name: @event_name, idempotency_key: @idempotency_key)
  end

  def event_attributes
    {
      user: @user,
      event_name: @event_name,
      occurred_at: @occurred_at,
      source: @source,
      metadata: @metadata,
      payload_json: build_payload,
      idempotency_key: @idempotency_key,
      make_delivery_status: initial_make_delivery_status
    }
  end

  def initial_make_delivery_status
    MakeWebhookEligibility.eligible_for_new_event?(
      user: @user,
      event_name: @event_name,
      suppress_make_delivery: @suppress_make_delivery
    ) ? "pending" : "disabled"
  end

  def enqueue_make_delivery(user_event)
    MakeWebhookDeliveryJob.perform_later(user_event.id)
  rescue => e
    Rails.logger.warn("[RelationshipEventTracker] Failed to enqueue Make delivery for event #{user_event.id}: #{e.message}")
  end

  def build_payload
    workout_sessions = safe_association(:workout_sessions)
    workout_plans = safe_association(:workout_plans)
    last_workout_at = relation_max(workout_sessions, :completed_at)
    total_workouts_completed = relation_count(workout_sessions)
    total_workouts_created = relation_count(workout_plans)
    segments = active_segments

    {
      "user_id" => @user.id,
      "email" => @user.email,
      "name" => @user.name,
      "locale" => "pt-BR",
      "event_name" => @event_name,
      "occurred_at" => @occurred_at.iso8601,
      "trial_status" => trial_status,
      "subscription_status" => subscription_status,
      "days_since_signup" => days_since(@user.created_at),
      "days_since_last_workout" => last_workout_at ? days_since(last_workout_at) : nil,
      "total_workouts_completed" => total_workouts_completed,
      "total_workouts_created" => total_workouts_created,
      "last_workout_at" => last_workout_at&.iso8601,
      "segment" => segments.first,
      "segments" => segments,
      "metadata" => @metadata
    }
  end

  def active_segments
    return [] unless @user.respond_to?(:user_segments)

    @user.user_segments.active.order(:segment_name).pluck(:segment_name)
  rescue ActiveRecord::StatementInvalid
    []
  end

  def trial_status
    return "active" if @user.trial_active?
    return "expired" if @user.trial_expired?

    "none"
  end

  def subscription_status
    @user.subscription&.status || "none"
  end

  def days_since(time)
    return nil unless time

    (Date.current - time.to_date).to_i
  end

  def safe_association(name)
    return unless @user.respond_to?(name)

    @user.public_send(name)
  rescue Exception
    nil
  end

  def relation_max(relation, column)
    return nil unless relation.respond_to?(:maximum)

    relation.maximum(column)
  rescue
    nil
  end

  def relation_count(relation)
    return 0 unless relation.respond_to?(:count)

    relation.count
  rescue
    0
  end
end
