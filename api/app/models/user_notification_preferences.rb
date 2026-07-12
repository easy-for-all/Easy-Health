# Per-user notification opt-in flags and activation-flow bookkeeping.
#
# IMPORTANT product separation (see privacy doc): this row governs FUNCTIONAL
# workout notifications only. It is NOT a marketing consent record — marketing
# lives on users.marketing_consent and must never be conflated with these flags.
#
# The "when the user trains" values (preferred_workout_period / time) are NOT
# stored here — HealthProfile is the source of truth. This row only mirrors the
# timezone optionally; users.time_zone is authoritative.
class UserNotificationPreferences < ApplicationRecord
  VARIANTS = %w[treatment control].freeze
  DISABLED_REASONS = %w[
    user_settings dislike_not_this_type dislike_too_many push_revoked account
  ].freeze

  belongs_to :user

  validates :user_id, uniqueness: true
  validates :max_pushes_per_week, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :activation_push_variant, inclusion: { in: VARIANTS }, allow_nil: true

  # True once both activation pushes (reminder + recovery) have been consumed or
  # the flow was explicitly ended — no further activation push may be sent.
  def activation_flow_completed?
    activation_notifications_completed_at.present?
  end

  def reminder_already_sent?
    activation_reminder_sent_at.present?
  end

  def recovery_already_sent?
    activation_recovery_sent_at.present?
  end
end
