class UserTrainingPreference < ApplicationRecord
  belongs_to :user

  validates :key,   presence: true
  validates :value, presence: true
  validates :key,   uniqueness: { scope: :user_id }

  scope :for_user, ->(u) { where(user: u) }

  def self.set(user:, key:, value:, source: "user", confidence: 1.0)
    find_or_initialize_by(user: user, key: key.to_s).tap do |pref|
      pref.update!(value: value.to_s, source: source, confidence: confidence, last_seen_at: Time.current)
    end
  end

  def self.get(user:, key:)
    find_by(user: user, key: key.to_s)&.value
  end
end
