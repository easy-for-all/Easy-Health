# Continuously re-links an AppInstallation to the authenticated user.
#
# The client sends X-Installation-Id on every request (see web/src/shared/lib/api.ts).
# Any authenticated request carrying it repairs the link, so a fire-and-forget
# register that never ran (or ran before sign_in) is no longer the only chance to
# associate the installation.
#
# Best-effort by design: never changes the response, never raises, never creates
# records, and never steals an installation already owned by another user.
module AppInstallationReconciliation
  extend ActiveSupport::Concern

  INSTALLATION_HEADER = "X-Installation-Id".freeze
  # An already-linked installation only rewrites last_authenticated_at once an
  # hour: without this every authenticated app request would be an UPDATE.
  TOUCH_INTERVAL = 1.hour

  included do
    after_action :reconcile_app_installation
  end

  private

  def reconcile_app_installation
    installation_id = request.headers[INSTALLATION_HEADER].presence&.strip
    return if installation_id.blank?
    return if current_user.nil?

    install = AppInstallation.find_by(installation_id: installation_id)
    return if install.nil? # creation belongs to installations#register only

    now = Time.current

    if install.user_id.nil?
      install.update_columns(user_id: current_user.id, last_authenticated_at: now, updated_at: now)
    elsif install.user_id == current_user.id
      last = install.last_authenticated_at
      return if last.present? && last > now - TOUCH_INTERVAL

      install.update_columns(last_authenticated_at: now, updated_at: now)
    else
      Rails.logger.warn(
        "[AppInstallation] association_conflict installation_id=#{installation_id} " \
        "owner_user_id=#{install.user_id} request_user_id=#{current_user.id}"
      )
    end
  rescue StandardError => e
    Rails.logger.warn("[AppInstallation] reconciliation_failed error=#{e.class}: #{e.message}")
  end
end
