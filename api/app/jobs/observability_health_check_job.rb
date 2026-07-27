# Runs the health checks, persists results and reconciles incidents.
#
# SCHEDULING: this job is invoked synchronously by `rake observability:check`
# from cron — it does NOT reschedule itself. The ActiveJob adapter here is
# :async (in-process), so a self-rescheduling checker would be silently dropped
# by the next deploy and the observability layer would be the first thing to go
# blind. The class exists so the logic stays adapter-portable the day a durable
# queue arrives; see docs/observability/ARCHITECTURE.md.
class ObservabilityHealthCheckJob < ApplicationJob
  queue_as :default

  def self.observability_heartbeat_key = "observability_health_check"

  def perform
    Observability::HealthCheckRunner.new.call
  end
end
