class BlockedEmail < ApplicationRecord
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  def self.blocked?(email)
    return false if email.blank?

    where(email: email.downcase.strip).exists?
  end

  def self.block!(email:, user_id: nil)
    create!(email: email.downcase.strip, user_id: user_id, blocked_at: Time.current)
  end
end
