# One evaluation of one check at one point in time.
#
# Kept as history (not just "latest state") so a question like "was registration
# already falling before that deploy?" is answerable without reconstructing it
# from logs. Pruned by rake observability:resolve_stale.
class ObservabilityCheckResult < ApplicationRecord
  STATUS_HEALTHY = "healthy".freeze
  STATUS_WARNING = "warning".freeze
  STATUS_CRITICAL = "critical".freeze
  # Not a fourth severity — an admission that the measurement could not be made.
  # current_value is NULL here, never 0.
  STATUS_INSUFFICIENT = "insufficient_data".freeze

  STATUSES = [ STATUS_HEALTHY, STATUS_WARNING, STATUS_CRITICAL, STATUS_INSUFFICIENT ].freeze
  SEVERITIES = %w[info warning critical].freeze

  validates :check_key, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :checked_at, presence: true

  scope :for_check, ->(key) { where(check_key: key.to_s) }
  scope :recent_first, -> { order(checked_at: :desc) }
  scope :since, ->(time) { where(checked_at: time..) }
  scope :alerting, -> { where(status: [ STATUS_WARNING, STATUS_CRITICAL ]) }

  # Latest result per check_key, in one query.
  def self.latest_per_check
    subquery = select("DISTINCT ON (check_key) *").order(:check_key, checked_at: :desc)
    from(subquery, :observability_check_results)
  end
end
