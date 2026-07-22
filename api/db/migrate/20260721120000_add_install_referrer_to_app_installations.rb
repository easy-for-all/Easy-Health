class AddInstallReferrerToAppInstallations < ActiveRecord::Migration[8.1]
  # Google Play Install Referrer (Fase 14). Captured ONCE per install (first valid
  # attribution, never overwritten by a blank) and never faked for old installs.
  # The native read requires a Play Install Referrer plugin (documented follow-up);
  # these columns receive the values via PATCH /app/installations when available.
  def change
    add_column :app_installations, :install_referrer, :string
    add_column :app_installations, :utm_source, :string
    add_column :app_installations, :utm_medium, :string
    add_column :app_installations, :utm_campaign, :string
    add_column :app_installations, :referrer_source, :string
    add_column :app_installations, :referrer_click_at, :datetime
    add_column :app_installations, :install_begin_at, :datetime
  end
end
