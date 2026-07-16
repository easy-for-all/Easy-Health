class ProductAnalyticsEvent < ApplicationRecord
  belongs_to :user, optional: true

  validates :event_name, presence: true
  validates :event_version, numericality: { only_integer: true, greater_than: 0 }
  validates :occurred_at, :received_at, presence: true
  validates :platform, inclusion: { in: Analytics::EventCatalog::PLATFORMS }
  validates :app_surface, inclusion: { in: Analytics::EventCatalog::APP_SURFACES }
  validates :environment, inclusion: { in: Analytics::EventCatalog::ENVIRONMENTS }

  # Events must belong to the canonical taxonomy (config/analytics/events.yml).
  validate :event_name_known

  scope :server_sink, -> { where(event_name: Analytics::EventCatalog.server_tracked) }
  scope :for_platform, ->(platform) { where(platform: platform) }
  scope :in_window, ->(range) { where(occurred_at: range) }

  private

  def event_name_known
    return if Analytics::EventCatalog.known?(event_name)

    errors.add(:event_name, "is not in the analytics taxonomy")
  end
end
