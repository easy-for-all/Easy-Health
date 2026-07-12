# One row per attempted activation push. Idempotency_key guarantees we never
# schedule/send the same reminder twice (unique partial index).
#
# payload_json NEVER contains the device token — only the deep-link data and
# non-sensitive context.
class NotificationDelivery < ApplicationRecord
  TYPES = %w[first_workout_reminder first_workout_recovery].freeze
  STATUSES = %w[scheduled sending sent failed opened converted canceled skipped].freeze

  belongs_to :user
  belongs_to :push_device, class_name: "DeviceToken", optional: true

  validates :notification_type, inclusion: { in: TYPES }
  validates :status, inclusion: { in: STATUSES }
  validates :idempotency_key, uniqueness: true, allow_nil: true

  scope :due, ->(now = Time.current) { where(status: "scheduled").where(scheduled_for: ..now) }
  scope :pending, -> { where(status: %w[scheduled sending]) }
  scope :of_type, ->(type) { where(notification_type: type) }

  # Cancel not-yet-sent deliveries (e.g. user started a workout / opted out).
  def self.cancel_pending_for(user, reason:, types: TYPES)
    pending.where(user_id: user.id, notification_type: Array(types)).find_each do |delivery|
      delivery.skip!(reason)
    end
  end

  def cancel!(reason)
    update!(status: "canceled", canceled_at: Time.current, cancel_reason: reason)
  end

  def skip!(reason)
    update!(status: "skipped", canceled_at: Time.current, cancel_reason: reason)
  end

  def terminal?
    %w[sent failed opened converted canceled skipped].include?(status)
  end
end
