# A stable per-installation record (see the migration and
# docs/android-tracking-audit.md). Keyed by a client-generated installation_id
# (random UUID), it can exist anonymously and be associated to a user after login.
#
# NEVER stores PII or the FCM token (linked via device_token_id instead).
class AppInstallation < ApplicationRecord
  PLATFORMS = Analytics::EventCatalog::PLATFORMS
  PERMISSION_STATUSES = DeviceToken::PERMISSION_STATUSES

  # Where the installation record originated. "register" = live tracking from the
  # app; "backfill_*" = inferred from an existing reliable source (never faked).
  SOURCES = %w[register backfill_device_token].freeze

  belongs_to :user, optional: true
  belongs_to :device_token, optional: true

  validates :installation_id, presence: true, uniqueness: true
  validates :platform, inclusion: { in: PLATFORMS }
  validates :notification_permission,
            inclusion: { in: PERMISSION_STATUSES }, allow_blank: true

  before_validation :normalize

  scope :for_platform, ->(platform) { where(platform: platform) }
  scope :authenticated, -> { where.not(user_id: nil) }
  scope :anonymous, -> { where(user_id: nil) }
  scope :active_since, ->(time) { where(last_seen_at: time..) }

  # Associate this install to a user after authentication. Idempotent; preserves
  # the anonymous history (first_seen_at/installed_at are never rewritten here).
  def associate_user!(target_user)
    return if target_user.nil? || user_id == target_user.id

    update!(user: target_user, last_authenticated_at: Time.current)
  end

  # Guard against accidentally exposing sensitive linkage in JSON.
  def as_json(options = {})
    super(options.merge(except: Array(options[:except]) + [:device_token_id]))
  end

  private

  def normalize
    self.platform = "unknown" unless PLATFORMS.include?(platform)
    # native must be coherent with an app platform; web/pwa are never native.
    self.native = false if %w[web pwa unknown].include?(platform)
    self.installation_id = installation_id.to_s.strip.presence
  end
end
