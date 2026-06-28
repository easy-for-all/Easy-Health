class BackfillMarketingConsentTrue < ActiveRecord::Migration[8.1]
  def up
    User.where(marketing_consent: false).update_all(marketing_consent: true)
  end

  def down
    # intentionally irreversible
  end
end
