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

  # Where a linking request came from. Purely descriptive: never an eligibility
  # rule, never inferred from the device manufacturer.
  #
  # "android_webview" is reserved and currently emitted by nothing — a Capacitor
  # WebView with the bridge is indistinguishable from a plain Android WebView
  # from the server side, so everything native reports "android_native".
  RUNTIME_CONTEXTS = %w[android_native android_webview web pwa unknown].freeze

  # Single source of truth for how long an installation_id may be. Both the
  # register endpoint and the header parser must agree: an id the register
  # accepts has to remain findable by AppInstallations::RequestContext, or it
  # would create rows that can never be linked.
  INSTALLATION_ID_MAX_BYTES = 128

  # app_build is a free-form string: nil, "", "unknown", "45" and "0045" all
  # coexist. The CASE guarantees the cast only ever runs on digits, so a single
  # malformed row can never break an aggregate query.
  NUMERIC_BUILD_SQL = "CASE WHEN app_build ~ '^[0-9]{1,9}$' THEN app_build::int END".freeze

  belongs_to :user, optional: true
  belongs_to :device_token, optional: true

  # Uma instalação pode ser dona de plano e sessão enquanto não existe conta.
  # dependent: :nullify em nenhum deles de propósito: o claim move a posse
  # explicitamente, e apagar uma instalação com plano anônimo dentro é um caso
  # que deve falhar alto, não perder o treino de alguém em silêncio.
  has_one  :anonymous_onboarding_session, dependent: :destroy
  has_many :workout_plans
  has_many :workout_sessions

  validates :installation_id, presence: true, uniqueness: true
  validates :platform, inclusion: { in: PLATFORMS }
  validates :notification_permission,
            inclusion: { in: PERMISSION_STATUSES }, allow_blank: true
  validates :runtime_context, inclusion: { in: RUNTIME_CONTEXTS }, allow_blank: true

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

  # There is deliberately NO associate_user! here. Linking is a transactional,
  # locked, conflict-aware operation with attempt bookkeeping — see
  # AppInstallations::LinkToUser, the only writer of user_id on this table.
  # A convenience method on the model is how a second, weaker semantics gets
  # reintroduced (the removed one overwrote another user's link without checking).

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
