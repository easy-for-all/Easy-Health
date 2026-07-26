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

  # Single source of truth for the build that started sending X-Installation-Id
  # on every authenticated request (app v1.0.45). Installs below it predate the
  # reconciliation and stay anonymous for reasons that are NOT a tracking bug,
  # so they must never be mixed into the current tracking health.
  RECONCILIATION_MIN_BUILD = 45

  # app_build is a free-form string: nil, "", "unknown", "45" and "0045" all
  # coexist. The CASE guarantees the cast only ever runs on digits, so a single
  # malformed row can never break an aggregate query.
  NUMERIC_BUILD_SQL = "CASE WHEN app_build ~ '^[0-9]{1,9}$' THEN app_build::int END".freeze

  belongs_to :user, optional: true
  belongs_to :device_token, optional: true

  validates :installation_id, presence: true, uniqueness: true
  validates :platform, inclusion: { in: PLATFORMS }
  validates :notification_permission,
            inclusion: { in: PERMISSION_STATUSES }, allow_blank: true

  before_validation :normalize

  scope :for_platform, ->(platform) { where(platform: platform) }
  scope :anonymous, -> { where(user_id: nil) }
  scope :active_since, ->(time) { where(last_seen_at: time..) }

  # Linked = we know WHICH user owns the install (user_id present). This is the
  # headline reconciliation metric.
  scope :linked, -> { where.not(user_id: nil) }

  # Fully authenticated = linked AND the link was confirmed by a real
  # authenticated request (last_authenticated_at). A linked install without it
  # is a data-quality signal, not a second definition of "linked".
  scope :fully_authenticated, -> { linked.where.not(last_authenticated_at: nil) }

  # @deprecated Misleading name: it only checks user_id, so it means "linked".
  #   Use .linked for reconciliation metrics or .fully_authenticated for
  #   confirmed authentication. Kept so existing callers keep working.
  scope :authenticated, -> { linked }

  scope :current_build, lambda {
    where(Arel.sql("(#{NUMERIC_BUILD_SQL}) >= #{RECONCILIATION_MIN_BUILD}"))
  }

  # Legacy = build below the threshold, absent or non-numeric.
  scope :legacy_build, lambda {
    where(Arel.sql("(#{NUMERIC_BUILD_SQL}) IS NULL OR (#{NUMERIC_BUILD_SQL}) < #{RECONCILIATION_MIN_BUILD}"))
  }

  # Associate this install to a user after authentication. Idempotent; preserves
  # the anonymous history (first_seen_at/installed_at are never rewritten here).
  def associate_user!(target_user)
    return if target_user.nil? || user_id == target_user.id

    update!(user: target_user, last_authenticated_at: Time.current)
  end

  # Guard against accidentally exposing sensitive linkage in JSON.
  def as_json(options = {})
    super(options.merge(except: Array(options[:except]) + [ :device_token_id ]))
  end

  private

  def normalize
    self.platform = "unknown" unless PLATFORMS.include?(platform)
    # native must be coherent with an app platform; web/pwa are never native.
    self.native = false if %w[web pwa unknown].include?(platform)
    self.installation_id = installation_id.to_s.strip.presence
  end
end
