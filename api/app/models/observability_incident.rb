# A problem that is currently happening (or was, until it resolved).
#
# Distinct from ObservabilityCheckResult: a check result is a measurement, an
# incident is the thing a human has to do something about. Many results collapse
# into one incident via `fingerprint`, so a check firing every 15 minutes for a
# day produces one row with occurrence_count = 96, not 96 rows.
#
# Written only by Observability::IncidentManager.
class ObservabilityIncident < ApplicationRecord
  SOURCES = %w[internal_check grafana sentry manual].freeze
  SEVERITIES = %w[warning critical].freeze

  STATUS_OPEN = "open".freeze
  STATUS_ACKNOWLEDGED = "acknowledged".freeze
  STATUS_RESOLVED = "resolved".freeze
  STATUSES = [ STATUS_OPEN, STATUS_ACKNOWLEDGED, STATUS_RESOLVED ].freeze

  # Open and acknowledged are both "still happening" — acknowledging says a
  # human has seen it, not that it stopped.
  ACTIVE_STATUSES = [ STATUS_OPEN, STATUS_ACKNOWLEDGED ].freeze

  validates :fingerprint, presence: true
  validates :source, inclusion: { in: SOURCES }
  validates :severity, inclusion: { in: SEVERITIES }
  validates :status, inclusion: { in: STATUSES }
  validates :title, presence: true

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :resolved, -> { where(status: STATUS_RESOLVED) }
  scope :critical, -> { where(severity: "critical") }
  scope :for_check, ->(key) { where(check_key: key.to_s) }
  scope :recent_first, -> { order(first_detected_at: :desc) }

  def active?
    ACTIVE_STATUSES.include?(status)
  end

  def duration_seconds(now: Time.current)
    ((resolved_at || now) - first_detected_at).to_i
  end

  def as_observability_json
    {
      id: id,
      source: source,
      check_key: check_key,
      title: title,
      description: description,
      severity: severity,
      status: status,
      current_value: current_value&.to_f,
      threshold_value: threshold_value&.to_f,
      dimensions: dimensions,
      first_detected_at: first_detected_at,
      last_detected_at: last_detected_at,
      acknowledged_at: acknowledged_at,
      resolved_at: resolved_at,
      duration_seconds: duration_seconds,
      occurrence_count: occurrence_count,
      notification_count: notification_count
    }
  end
end
