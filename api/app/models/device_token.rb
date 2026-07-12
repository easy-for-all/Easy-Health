class DeviceToken < ApplicationRecord
  PLATFORMS = %w[android ios].freeze
  # Values reported by the client from Capacitor's permission API.
  PERMISSION_STATUSES = %w[granted denied prompt prompt-with-rationale].freeze

  belongs_to :user

  validates :token, presence: true, uniqueness: true
  validates :platform, inclusion: { in: PLATFORMS }

  scope :active, -> { where(enabled: true, invalidated_at: nil) }

  # Soft-disable a token FCM reported as gone (UNREGISTERED/INVALID_ARGUMENT).
  # History is kept — we never destroy tokens on invalidation.
  def invalidate!(reason)
    update!(enabled: false, invalidated_at: Time.current, invalidation_reason: reason)
  end

  # Never leak the raw token. Used for logs/admin.
  def masked_token
    return nil if token.blank?

    "#{token[0, 6]}…#{token[-4, 4]}"
  end

  # Guard against accidentally exposing the token in JSON responses/admin.
  def as_json(options = {})
    super(options.merge(except: Array(options[:except]) + [:token]))
  end
end
