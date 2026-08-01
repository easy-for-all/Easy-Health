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
    # Kept so the rescue below can still key its event when the failure happened
    # after the context was read.
    @app_installation_context = context
    Observability::Events.installation_link_attempted(user: current_user)

    install = AppInstallation.find_by(installation_id: context.installation_id)
    if install.nil? # creation belongs to installations#register only
      # The client believes it has an installation the server has never seen.
      # Not fatal, but it is exactly the shape of a broken register call.
      Rails.logger.info(
        {
          event: "installation_link_deferred",
          producer: "reconciliation",
          installation_id_hash: context.installation_id_hash,
          user_id: current_user.id,
          source: "reconciliation",
          runtime_context: context.runtime_context,
          status: "not_found",
          failure_code: "installation_not_found",
          build_number: context.build_number
        }.compact.to_json
      )
      emit_link_failure("not_found")
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
    emit_link_failure("error")
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
      # Only fires on the transition to linked; the steady state is
      # :already_linked, which emits nothing. No throttling needed.
      Observability::Events.installation_link_succeeded(user: current_user, result: "linked")
    when :conflict
      emit_link_failure("conflict")
    when :not_found
      emit_link_failure("not_found")
    when :validation_failed, :unexpected_error, :invalid_input
      emit_link_failure("error")
    end
  end

  def emit_link_failure(label)
    Observability::Events.installation_link_failed(
      user: current_user,
      result: label,
      idempotency_key: link_failure_idempotency_key(label)
    )
  end

  # One representative row per (installation, user, failure kind) per reporting
  # day. This runs on every authenticated request, so an unresolvable failure —
  # a conflict that will never link, or a client believing in an installation
  # the server never saw — used to write one row per API call the app made.
  #
  # Deduplication is the database's job: the partial unique index on
  # idempotency_key plus the RecordNotUnique rescue in Analytics::ServerEvents.
  # That survives restarts and works across processes, unlike a cache.
  #
  # A DAY (not "ever") so a problem that is still happening stays visible in the
  # 24h/7d windows of the panel instead of disappearing after its first sighting.
  # The date comes from the analytics reporting zone (America/Sao_Paulo), so the
  # bucket matches how every other daily figure is cut — a conflict at 22h local
  # belongs to that evening, not to the next UTC day.
  #
  # installation_id_hash, never the raw installation_id: this key reaches error
  # messages and technical logs, and the raw value is a stable device identifier.
  # A blank key means "could not deduplicate safely" and falls back to emitting,
  # because losing a failure silently is worse than recording it twice.
  def link_failure_idempotency_key(label)
    hash = @app_installation_context&.installation_id_hash
    return nil if hash.blank? || current_user.nil?

    "install_link_failed:#{hash}:#{label}:u#{current_user.id}:#{Analytics::ReportingTime.today}"
  end
end
