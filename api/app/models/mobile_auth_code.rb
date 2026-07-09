require "digest"

class MobileAuthCode < ApplicationRecord
  CODE_TTL = 5.minutes
  PLATFORMS = %w[android ios].freeze

  class Error < StandardError; end
  class InvalidCodeError < Error; end
  class ExpiredCodeError < Error; end
  class UsedCodeError < Error; end
  class InvalidPlatformError < Error; end

  belongs_to :user

  validates :code_digest, presence: true, uniqueness: true
  validates :platform, presence: true, inclusion: { in: PLATFORMS }
  validates :expires_at, presence: true

  def self.issue_for!(user:, platform:)
    normalized_platform = normalize_platform!(platform)
    code = SecureRandom.urlsafe_base64(32)

    create!(
      user: user,
      platform: normalized_platform,
      code_digest: digest(code),
      expires_at: CODE_TTL.from_now
    )

    code
  end

  def self.redeem!(code:, platform:)
    normalized_code = code.to_s.strip
    raise InvalidCodeError if normalized_code.blank?

    normalized_platform = normalize_platform!(platform)

    transaction do
      auth_code = lock.find_by(code_digest: digest(normalized_code), platform: normalized_platform)
      raise InvalidCodeError if auth_code.nil?
      raise UsedCodeError if auth_code.used_at.present?
      raise ExpiredCodeError if auth_code.expires_at <= Time.current

      auth_code.update!(used_at: Time.current)
      auth_code
    end
  end

  def self.digest(code)
    Digest::SHA256.hexdigest(code.to_s)
  end

  def self.normalize_platform!(platform)
    normalized_platform = platform.to_s.strip.downcase
    raise InvalidPlatformError unless PLATFORMS.include?(normalized_platform)

    normalized_platform
  end
end
