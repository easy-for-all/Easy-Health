class BackfillUserReferralAndPublicProfile < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    # Backfill referral codes for users without one
    User.where(referral_code: nil).find_each do |user|
      loop do
        code = SecureRandom.alphanumeric(8).upcase
        unless User.exists?(referral_code: code)
          user.update_column(:referral_code, code)
          break
        end
      end
    end

    # Backfill public profiles for users without one
    User.left_joins(:public_profile)
        .where(public_profiles: { id: nil })
        .find_each do |user|
      PublicProfile.create!(user: user, display_name: user.name)
    end
  end

  def down
    # irreversible
  end
end
