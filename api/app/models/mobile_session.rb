require "digest"

# Opaque, revocable session token for native shells that cannot carry the
# Devise cookie.
#
# The iOS app ships its web assets inside the IPA (App Store guideline 2.5.2),
# so its origin is capacitor://localhost rather than easyhealth.art. The session
# cookie is SameSite=Lax and therefore is not sent on those cross-site requests,
# and widening it to SameSite=None would both weaken Web/Android and still lose
# to WKWebView's third-party cookie blocking. So native clients authenticate
# with a bearer token instead.
#
# Deliberately opaque rather than a JWT: the value of this table is that a
# session can be revoked (logout, account deletion, admin action) and that
# revocation takes effect on the very next request. A self-describing token
# cannot do that without a revocation list, which is this table anyway.
#
# Mirrors MobileAuthCode: SHA-256 digest at rest, raw value returned once.
class MobileSession < ApplicationRecord
  DEFAULT_TTL_DAYS = 90
  # Teto de sessões ativas por usuário quando não há installation_id para
  # escopar a rotação. Sem ele, um cliente que reautentica em loop acumularia
  # credenciais válidas indefinidamente.
  MAX_ACTIVE_PER_USER = 10
  TOKEN_PREFIX = "ehs_".freeze
  TOKEN_BYTES = 32
  PLATFORMS = %w[android ios].freeze
  REVOCATION_REASONS = %w[
    user_signout
    account_deleted
    admin_revoked
    superseded
  ].freeze

  # Writing last_used_at on every authenticated request would turn every GET
  # into a write. One update per interval is enough to answer "is this device
  # still active?" without that cost.
  LAST_USED_THROTTLE = 15.minutes

  class Error < StandardError; end
  class InvalidPlatformError < Error; end

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :expires_at, presence: true
  validates :revocation_reason, inclusion: { in: REVOCATION_REASONS }, allow_nil: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  def self.ttl
    days = ENV.fetch("MOBILE_SESSION_TTL_DAYS", DEFAULT_TTL_DAYS).to_i
    days = DEFAULT_TTL_DAYS unless days.positive?
    days.days
  end

  # Returns the raw token. It is not recoverable afterwards — callers must hand
  # it to the client in the same response.
  def self.issue_for!(user:, platform:, installation_id: nil, app_version: nil)
    normalized_platform = normalize_platform!(platform)
    token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(TOKEN_BYTES)}"

    transaction do
      supersede_previous!(user: user, installation_id: installation_id.presence)

      create!(
        user: user,
        platform: normalized_platform,
        installation_id: installation_id.presence,
        app_version: app_version.presence,
        token_digest: digest(token),
        expires_at: ttl.from_now
      )
    end

    token
  end

  # Política de rotação, deliberada:
  #
  # Reautenticar NO MESMO aparelho substitui a sessão anterior daquele aparelho.
  # É o comportamento que o usuário espera — ele não criou um segundo acesso, ele
  # renovou o dele — e evita acumular credenciais válidas esquecidas.
  #
  # Reautenticar NÃO derruba os outros aparelhos. Entrar no iPhone não pode
  # deslogar o iPad: isso seria uma decisão de produto que ninguém pediu, e
  # transformaria um login rotineiro em perda de sessão alheia.
  #
  # Sem installation_id não dá para saber qual aparelho é qual, então cai no teto
  # global por usuário, mantendo as mais recentes.
  def self.supersede_previous!(user:, installation_id:)
    if installation_id.present?
      active.where(user_id: user.id, installation_id: installation_id)
            .update_all(revoked_at: Time.current, revocation_reason: "superseded", updated_at: Time.current)
      return
    end

    surplus = active.where(user_id: user.id)
                    .order(created_at: :desc)
                    .offset(MAX_ACTIVE_PER_USER - 1)
                    .pluck(:id)
    return if surplus.empty?

    where(id: surplus).update_all(
      revoked_at: Time.current, revocation_reason: "superseded", updated_at: Time.current
    )
  end

  # Nil for anything that must not authenticate: unknown, expired, revoked, or
  # belonging to an account that can no longer sign in. Callers cannot tell the
  # cases apart, and should not — the client's only useful response to any of
  # them is to discard the token and re-authenticate.
  def self.authenticate(raw_token)
    normalized = raw_token.to_s.strip
    return nil if normalized.blank?

    session = active.find_by(token_digest: digest(normalized))
    return nil if session.nil?
    return nil unless session.user.active_for_authentication?

    session.touch_last_used!
    session
  end

  def self.revoke_all_for!(user, reason:)
    active.where(user_id: user.id).update_all(
      revoked_at: Time.current,
      revocation_reason: reason,
      updated_at: Time.current
    )
  end

  def self.digest(token)
    Digest::SHA256.hexdigest(token.to_s)
  end

  def self.normalize_platform!(platform)
    normalized = platform.to_s.strip.downcase
    raise InvalidPlatformError unless PLATFORMS.include?(normalized)

    normalized
  end

  def revoke!(reason:)
    update!(revoked_at: Time.current, revocation_reason: reason)
  end

  def touch_last_used!
    return if last_used_at.present? && last_used_at > LAST_USED_THROTTLE.ago

    update_columns(last_used_at: Time.current, updated_at: Time.current)
  end
end
