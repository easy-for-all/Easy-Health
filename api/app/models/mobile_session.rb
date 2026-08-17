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
  SESSION_TTL = 90.days
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

  # Returns the raw token. It is not recoverable afterwards — callers must hand
  # it to the client in the same response.
  def self.issue_for!(user:, platform:, installation_id: nil, app_version: nil)
    normalized_platform = normalize_platform!(platform)
    token = "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(TOKEN_BYTES)}"

    create!(
      user: user,
      platform: normalized_platform,
      installation_id: installation_id.presence,
      app_version: app_version.presence,
      token_digest: digest(token),
      expires_at: SESSION_TTL.from_now
    )

    token
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
