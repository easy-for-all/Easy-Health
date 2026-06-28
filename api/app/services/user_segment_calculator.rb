class UserSegmentCalculator
  Result = Struct.new(:user_id, :active_segments, :segment_changes, :created_or_activated, :deactivated, keyword_init: true)

  def self.call(user, dry_run: false)
    new(user).call(dry_run: dry_run)
  end

  def initialize(user)
    @user = user
  end

  def call(dry_run: false)
    desired = desired_segments
    current = @user.user_segments.index_by(&:segment_name)

    return dry_run_result(desired, current) if dry_run

    created_or_activated = 0
    deactivated = 0

    UserSegment.transaction do
      desired.each do |segment_name, attrs|
        segment = current[segment_name] || @user.user_segments.build(segment_name: segment_name)
        changed = segment.new_record? || !segment.active? ||
                  segment.reason != attrs[:reason] ||
                  segment.metadata_json != attrs[:metadata_json]
        next unless changed

        segment.assign_attributes(
          active: true,
          reason: attrs[:reason],
          metadata_json: attrs[:metadata_json],
          calculated_at: Time.current
        )
        segment.save!
        created_or_activated += 1
      end

      (current.keys - desired.keys).each do |segment_name|
        segment = current[segment_name]
        next unless segment&.active?

        segment.update!(active: false, calculated_at: Time.current)
        deactivated += 1
      end
    end

    Result.new(
      user_id: @user.id,
      active_segments: desired.keys.sort,
      segment_changes: created_or_activated + deactivated,
      created_or_activated: created_or_activated,
      deactivated: deactivated
    )
  end

  private

  def dry_run_result(desired, current)
    created_or_activated = desired.count do |segment_name, attrs|
      segment = current[segment_name]
      segment.nil? || !segment.active? || segment.reason != attrs[:reason] || segment.metadata_json != attrs[:metadata_json]
    end
    deactivated = (current.keys - desired.keys).count { |segment_name| current[segment_name]&.active? }

    Result.new(
      user_id: @user.id,
      active_segments: desired.keys.sort,
      segment_changes: created_or_activated + deactivated,
      created_or_activated: created_or_activated,
      deactivated: deactivated
    )
  end

  def desired_segments
    segments = {}
    add(segments, "trial_active", "trial active without paid subscription") if trial_active_without_subscription?
    add(segments, "trial_expiring_soon", "trial ends within 48 hours") if trial_expiring_soon?
    add(segments, "trial_expired", "trial expired without paid subscription") if trial_expired_without_subscription?
    add(segments, "subscriber_active", "subscription active") if subscriber_active?
    add(segments, "subscriber_canceled", "subscription canceled or canceling") if subscriber_canceled?
    add(segments, "never_created_workout", "no workout plan created") if workout_plans_count.zero?
    add(segments, "workout_created_not_started", "workout plan exists but no session") if workout_plans_count.positive? && workout_sessions_count.zero?
    add(segments, "first_workout_done", "at least one workout completed") if workout_sessions_count.positive?
    add(segments, "active_user", "two or more workouts in the last seven days") if workouts_last_7_days >= 2
    add(segments, "inactive_3_days", "last workout at least three days ago") if inactive_for?(3)
    add(segments, "inactive_7_days", "last workout at least seven days ago") if inactive_for?(7)
    add(segments, "inactive_15_days", "last workout at least fifteen days ago") if inactive_for?(15)
    add(segments, "high_intent_trial", "trial user created and completed a workout") if trial_active_without_subscription? && workout_plans_count.positive? && workout_sessions_count.positive?
    add(segments, "churn_risk", "active subscriber inactive for seven days") if subscriber_active? && churn_risk?
    add(segments, "returning_user", "recent workout after prior inactivity") if returning_user?
    add(segments, "uploaded_body_photo", "has body photo") if body_photo_count.positive?
    add(segments, "no_body_photo", "has no body photo") if body_photo_count.zero?
    add(segments, "completed_partial_recently", "partial workout in the last seven days") if partial_recently?
    segments
  end

  def add(segments, segment_name, reason)
    segments[segment_name] = {
      reason: reason,
      metadata_json: metadata_for(segment_name)
    }
  end

  def metadata_for(segment_name)
    {
      "segment_name" => segment_name,
      "workout_plans_count" => workout_plans_count,
      "workout_sessions_count" => workout_sessions_count,
      "last_workout_at" => last_workout_at&.iso8601,
      "trial_ends_at" => @user.trial_ends_at&.iso8601,
      "subscription_status" => @user.subscription&.status,
      "body_photo_count" => body_photo_count
    }
  end

  def trial_active_without_subscription?
    @user.trial_active? && !subscriber_active?
  end

  def trial_expiring_soon?
    trial_active_without_subscription? && @user.trial_ends_at <= 48.hours.from_now
  end

  def trial_expired_without_subscription?
    @user.trial_expired? && !subscriber_active?
  end

  def subscriber_active?
    @user.subscription&.status&.in?(%w[active trialing])
  end

  def subscriber_canceled?
    sub = @user.subscription
    sub&.status == "canceled" || sub&.cancel_at_period_end?
  end

  def inactive_for?(days)
    last_workout_at.present? && last_workout_at <= days.days.ago
  end

  def churn_risk?
    return true if last_workout_at.nil? && @user.created_at <= 7.days.ago

    inactive_for?(7)
  end

  def returning_user?
    return false unless last_workout_at.present? && last_workout_at >= 7.days.ago

    @user.user_events.where(event_name: %w[user_inactive_3_days user_inactive_7_days user_inactive_15_days]).exists?
  end

  def partial_recently?
    @user.workout_sessions
         .where(completion_status: "completed_partial")
         .where(completed_at: 7.days.ago..)
         .exists?
  end

  def workouts_last_7_days
    @workouts_last_7_days ||= @user.workout_sessions.where(completed_at: 7.days.ago..).count
  end

  def workout_plans_count
    @workout_plans_count ||= @user.workout_plans.count
  end

  def workout_sessions_count
    @workout_sessions_count ||= @user.workout_sessions.count
  end

  def body_photo_count
    @body_photo_count ||= @user.user_media.where(category: "body_photo").count
  end

  def last_workout_at
    @last_workout_at ||= @user.workout_sessions.maximum(:completed_at)
  end
end
