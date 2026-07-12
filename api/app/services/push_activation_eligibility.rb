# Single source of truth for whether an activation push may be scheduled/sent.
# Mirrors the ENV-flag + eligibility pattern of MakeWebhookEligibility.
#
# `reason_ineligible` returns nil when eligible, or a short machine reason used
# for admin metrics and notification_skipped events. `should_send?` additionally
# excludes the experiment control group (which stays eligible for tracking but
# never receives a push).
class PushActivationEligibility
  # Minimum spacing between the two activation pushes (~1 day) and cooldown so we
  # never send two activation pushes within the same window.
  ACTIVATION_COOLDOWN = 20.hours
  RECOVERY_MIN_GAP = 20.hours

  class << self
    def enabled?
      flag?("ACTIVATION_PUSH_ENABLED")
    end

    def experiment_enabled?
      flag?("ACTIVATION_PUSH_EXPERIMENT_ENABLED")
    end

    def configured?
      enabled? && FirebasePushService.configured?
    end

    def eligible?(user, notification_type:)
      reason_ineligible(user, notification_type: notification_type).nil?
    end

    # Eligible AND allocated to treatment. Control is intentionally suppressed.
    def should_send?(user, notification_type:)
      return false unless eligible?(user, notification_type: notification_type)

      ExperimentAssignment.variant_for(user) == "treatment"
    end

    def reason_ineligible(user, notification_type:)
      return "flag_disabled" unless enabled?
      return "unknown_type" unless NotificationDelivery::TYPES.include?(notification_type)

      prefs = user.notification_preferences
      return "no_preferences" if prefs.nil?
      return "push_disabled" unless prefs.push_enabled?
      return "reminders_disabled" unless prefs.workout_reminders_enabled?
      return "opted_out" if prefs.notifications_disabled_at.present?
      return "flow_completed" if prefs.activation_flow_completed?
      return "no_active_device" unless user.device_tokens.active.exists?
      return "no_access" unless user.has_active_access?
      return "no_plan" unless user.workout_plans.exists?
      return "already_engaged" if user.workout_sessions.exists?
      return "no_preferred_time" if user.health_profile&.preferred_workout_time.blank?

      per_type_reason(prefs, notification_type) || cooldown_reason(prefs)
    end

    private

    def per_type_reason(prefs, notification_type)
      case notification_type
      when "first_workout_reminder"
        "already_sent" if prefs.reminder_already_sent?
      when "first_workout_recovery"
        return "reminder_not_sent" unless prefs.reminder_already_sent?
        return "already_sent" if prefs.recovery_already_sent?

        "too_soon" if prefs.activation_reminder_sent_at > RECOVERY_MIN_GAP.ago
      end
    end

    def cooldown_reason(prefs)
      last_sent = [prefs.activation_reminder_sent_at, prefs.activation_recovery_sent_at].compact.max
      "within_cooldown" if last_sent && last_sent > ACTIVATION_COOLDOWN.ago
    end

    def flag?(name)
      ActiveModel::Type::Boolean.new.cast(ENV.fetch(name, "false"))
    end
  end
end
