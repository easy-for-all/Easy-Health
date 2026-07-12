# Shared logic for the activation-push schedulers. Subclasses define the
# notification type, how to find candidates, and the local time to schedule for.
#
# Creates an idempotent `scheduled` NotificationDelivery per eligible user. The
# actual send happens later in DispatchDuePushJob when scheduled_for arrives.
# Run via external cron (see lib/tasks/push_activation.rake) — no in-repo cron.
class ActivationPushSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    stats = Hash.new(0)
    candidate_user_ids.each do |user_id|
      user = User.find_by(id: user_id)
      next unless user

      stats[:candidates] += 1
      next if PushActivationEligibility.reason_ineligible(user, notification_type: notification_type)

      scheduled_for = scheduled_time_for(user)
      next if scheduled_for.nil?

      stats[:scheduled] += 1 if schedule!(user, scheduled_for)
    end
    Rails.logger.info("[#{self.class.name}] #{stats.inspect}")
    stats
  end

  private

  def schedule!(user, scheduled_for)
    plan_id = latest_plan_id(user)
    return false if plan_id.nil?

    idempotency_key = "#{notification_type}:#{user.id}:#{plan_id}"
    return false if NotificationDelivery.exists?(idempotency_key: idempotency_key)

    delivery = NotificationDelivery.create!(
      user: user,
      notification_type: notification_type,
      status: "scheduled",
      scheduled_for: scheduled_for,
      idempotency_key: idempotency_key,
      payload_json: { "scheduled_local_hour" => scheduled_for.hour }
    )
    track_scheduled(user, delivery, scheduled_for)
    true
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    false # already scheduled for this user+plan (race) — idempotent
  end

  def track_scheduled(user, delivery, scheduled_for)
    UserEventService.track(
      user: user,
      event_name: "push_scheduled",
      source: "activation_push",
      suppress_make_delivery: true,
      metadata: {
        notification_type: notification_type,
        delivery_id: delivery.id,
        scheduled_local_hour: scheduled_for.hour,
        platform: "android"
      }
    )
  end

  def latest_plan_id(user)
    user.workout_plans.order(created_at: :desc).limit(1).pick(:id)
  end

  def notification_type
    raise NotImplementedError, "#{self.class} must implement #notification_type"
  end

  def candidate_user_ids
    raise NotImplementedError, "#{self.class} must implement #candidate_user_ids"
  end

  def scheduled_time_for(_user)
    raise NotImplementedError, "#{self.class} must implement #scheduled_time_for"
  end
end
