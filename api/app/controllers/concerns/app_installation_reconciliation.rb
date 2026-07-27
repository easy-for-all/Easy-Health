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

  included do
    after_action :reconcile_app_installation
  end

  private

  def reconcile_app_installation
    return @app_installation_link_result if defined?(@app_installation_reconciled) && @app_installation_reconciled

    context = AppInstallations::RequestContext.from(request)
    return unless context.present?
    return if current_user.nil?

    @app_installation_reconciled = true
    Observability::Events.installation_link_attempted(user: current_user)

    install = AppInstallation.find_by(installation_id: context.installation_id)
    if install.nil? # creation belongs to installations#register only
      # The client believes it has an installation the server has never seen.
      # Not fatal, but it is exactly the shape of a broken register call.
      Rails.logger.info(
        {
          event: "installation_link_deferred",
          installation_id_hash: context.installation_id_hash,
          user_id: current_user.id,
          source: "reconciliation",
          runtime_context: context.runtime_context,
          status: "not_found",
          failure_code: "installation_not_found",
          build_number: context.build_number
        }.compact.to_json
      )
      Observability::Events.installation_link_failed(user: current_user, result: "not_found")
      @app_installation_link_result = AppInstallations::LinkToUser.not_found
      return @app_installation_link_result
    end

    record_authenticated_request!(install)
    @app_installation_link_result = AppInstallations::LinkToUser.call(
      installation: install,
      user: current_user,
      source: "reconciliation",
      runtime_context: context.runtime_context,
      build_number: context.build_number
    )
    record_link_event(@app_installation_link_result)
    @app_installation_link_result
  rescue StandardError => e
    Rails.logger.warn("[AppInstallation] reconciliation_failed error=#{e.class}: #{e.message}")
    Observability::Events.installation_link_failed(user: current_user, result: "error")
    @app_installation_link_result = AppInstallations::LinkToUser::Result.new(
      success: false,
      status: :unexpected_error,
      installation: nil,
      failure_code: "unexpected_error"
    )
  end

  def record_authenticated_request!(install)
    return if install.first_authenticated_request_at.present?

    now = Time.current
    install.update_columns(first_authenticated_request_at: now, updated_at: now)
  end

  def record_link_event(result)
    case result.status
    when :linked
      Observability::Events.installation_link_succeeded(user: current_user, result: "linked")
    when :conflict
      Observability::Events.installation_link_failed(user: current_user, result: "conflict")
    when :not_found
      Observability::Events.installation_link_failed(user: current_user, result: "not_found")
    when :validation_failed, :unexpected_error, :invalid_input
      Observability::Events.installation_link_failed(user: current_user, result: "error")
    end
  end
end
