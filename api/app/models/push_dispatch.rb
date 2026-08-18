# Audit + idempotency record for a push requested by the Make orchestrator.
#
# Make decides WHEN/IF/which template to send; this row is the technical
# side: it proves what EasyHealth was asked to do and what actually happened
# (skipped, sent, provider-accepted, opened). It NEVER stores a device token —
# neither the column set nor `payload_json` may carry one.
class PushDispatch < ApplicationRecord
  STATUSES = %w[
    received deferred skipped processing provider_accepted partially_accepted failed opened
  ].freeze

  ALLOWED_TRANSITIONS = {
    "received" => %w[deferred skipped processing failed],
    "deferred" => %w[processing skipped],
    "processing" => %w[deferred skipped provider_accepted partially_accepted failed],
    "failed" => %w[deferred skipped processing failed],
    "provider_accepted" => %w[opened],
    "partially_accepted" => %w[opened],
    "opened" => []
  }.freeze

  # Terminal states where a real send already reached FCM — a repeat request
  # with the same idempotency_key must NOT be re-sent (Phase 9).
  DELIVERED_STATUSES = %w[provider_accepted partially_accepted opened].freeze

  # stale_scheduled_reminder and stale_after_quiet_hours are NOT synonyms:
  #   stale_scheduled_reminder  — target_workout_at has already passed, so the
  #                               content lost its validity (late redrive).
  #   stale_after_quiet_hours   — the quiet-hours release would land after the
  #                               target, so deferring is pointless.
  SKIP_REASONS = %w[
    orchestration_disabled user_not_found no_preferences global_opt_out category_opt_out
    no_active_token permission_denied duplicate invalid_payload rate_limited
    frequency_capped cooldown_active stale_after_quiet_hours stale_scheduled_reminder
  ].freeze

  DEFER_REASONS = %w[quiet_hours].freeze
  DEFERRABLE_SKIP_REASONS = [].freeze

  belongs_to :user
  # The business event this push was requested for. Nullable: Make may send a
  # dispatch we cannot resolve to an event, and those must stay visible as
  # "not correlated" rather than being rejected.
  belongs_to :user_event, optional: true

  validates :notification_type, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validate :status_transition_allowed, if: :will_save_change_to_status?

  scope :deferred_due, ->(now = Time.current) { where(status: "deferred").where(next_allowed_at: ..now) }

  # True once FCM already accepted this dispatch for at least one device.
  def delivered?
    DELIVERED_STATUSES.include?(status)
  end

  def deferred?
    status == "deferred"
  end

  def defer_reason
    payload_json["defer_reason"].presence
  end

  def mark_deferred!(reason:, next_allowed_at:)
    update!(
      status: "deferred",
      skip_reason: nil,
      next_allowed_at: next_allowed_at,
      payload_json: payload_json.merge("defer_reason" => reason)
    )
  end

  # Stamp the open (idempotent). Promotes an accepted dispatch to "opened";
  # leaves a failed/skipped row's status untouched but still records opened_at.
  def mark_opened!
    promotable = %w[provider_accepted partially_accepted].include?(status)
    update!(status: promotable ? "opened" : status, opened_at: opened_at || Time.current)
  end

  # Guard against ever leaking a token through JSON (defense in depth; the row
  # is not supposed to contain one in the first place).
  def as_json(options = {})
    super(options.merge(except: Array(options[:except]) + [ :payload_json ]))
  end

  private

  def status_transition_allowed
    return unless persisted?

    from = status_in_database
    return if from.blank? || from == status

    errors.add(:status, "cannot transition from #{from} to #{status}") unless ALLOWED_TRANSITIONS.fetch(from, []).include?(status)
  end
end
