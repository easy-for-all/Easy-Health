module Observability
  # Runs every check, persists the results and reconciles incidents.
  #
  # Isolation is the contract: one check raising must not stop the others. A
  # runner that aborts halfway leaves the remaining checks silently unevaluated
  # — the exact blindness this layer exists to remove — so BaseCheck.run
  # converts any exception into an insufficient_data result and the run
  # continues.
  class HealthCheckRunner
    CHECKS = [
      Observability::Checks::AndroidRegistrationConversionCheck,
      Observability::Checks::AndroidInstallationLinkCheck,
      Observability::Checks::GoogleAuthHealthCheck,
      Observability::Checks::JobsIntegrationsCheck,
      Observability::Checks::ApiHealthCheck
    ].freeze

    Summary = Struct.new(:results, :incidents_opened, :incidents_resolved, :failed_checks, :duration_ms,
                         keyword_init: true)

    def call
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      checked_at = Time.current

      results = CHECKS.flat_map { |check| check.run }

      results.each { |result| result.persist!(checked_at: checked_at) }

      opened_before = ObservabilityIncident.active.count
      results.each { |result| Observability::IncidentManager.reconcile(result) }
      opened_after = ObservabilityIncident.active.count

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

      summary = Summary.new(
        results: results,
        incidents_opened: [ opened_after - opened_before, 0 ].max,
        incidents_resolved: [ opened_before - opened_after, 0 ].max,
        failed_checks: results.count(&:insufficient?),
        duration_ms: duration_ms
      )

      log_summary(summary)
      summary
    end

    private

    def log_summary(summary)
      by_status = summary.results.group_by(&:status).transform_values(&:size)

      Observability::Logger.emit(
        "observability_check_completed",
        level: :info,
        result: "success",
        duration_ms: summary.duration_ms,
        metadata: {
          checks: summary.results.size,
          healthy: by_status[Observability::CheckResult::HEALTHY].to_i,
          warning: by_status[Observability::CheckResult::WARNING].to_i,
          critical: by_status[Observability::CheckResult::CRITICAL].to_i,
          insufficient_data: by_status[Observability::CheckResult::INSUFFICIENT].to_i,
          incidents_opened: summary.incidents_opened,
          incidents_resolved: summary.incidents_resolved
        }
      )
    end
  end
end
