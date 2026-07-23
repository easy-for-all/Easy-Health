# Audit + idempotency record for a push requested by the Make orchestrator.
#
# Make decides WHEN/IF/which template to send; this row is the technical
# side: it proves what EasyHealth was asked to do and what actually happened
# (skipped, sent, provider-accepted, opened). It NEVER stores a device token —
# neither the column set nor `payload_json` may carry one.
class PushDispatch < ApplicationRecord
  STATUSES = %w[
    received skipped processing provider_accepted partially_accepted failed opened
  ].freeze

  # Terminal states where a real send already reached FCM — a repeat request
  # with the same idempotency_key must NOT be re-sent (Phase 9).
  DELIVERED_STATUSES = %w[provider_accepted partially_accepted opened].freeze

  SKIP_REASONS = %w[
    orchestration_disabled user_not_found no_preferences global_opt_out category_opt_out
    no_active_token permission_denied duplicate invalid_payload rate_limited
    frequency_capped cooldown_active
  ].freeze

  belongs_to :user

  validates :notification_type, presence: true
  validates :idempotency_key, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  # True once FCM already accepted this dispatch for at least one device.
  def delivered?
    DELIVERED_STATUSES.include?(status)
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
end
