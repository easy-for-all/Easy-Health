# Gives every ActiveJob a correlation context, structured job_* events and,
# when the job maps to a registered heartbeat, a liveness record.
#
# Correlation across the enqueue boundary: the request_id that enqueued the job
# is serialized into the job payload and restored on perform, so a log line
# written inside a job can be traced back to the HTTP request that triggered it.
# This works with the current :async adapter and with any durable adapter later.
#
# Heartbeats are opt-in per job (`observability_heartbeat_key`) rather than
# automatic: a heartbeat means "this is expected to run on a schedule", and most
# jobs here are event-triggered, so a missing run is not a fault.
module ObservabilityInstrumented
  extend ActiveSupport::Concern

  included do
    attr_accessor :observability_request_id

    around_perform do |job, block|
      job.run_with_observability(&block)
    end
  end

  class_methods do
    # Subclasses override to opt into heartbeat tracking.
    def observability_heartbeat_key
      nil
    end
  end

  def serialize
    super.merge("observability_request_id" => observability_request_id || Observability::Context.request_id)
  end

  def deserialize(job_data)
    super
    self.observability_request_id = job_data["observability_request_id"]
  end

  def job_key
    self.class.name.to_s.underscore
  end

  def run_with_observability
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    heartbeat_key = self.class.observability_heartbeat_key

    setup_context
    Observability::Events.job_started(job_key: job_key)
    Observability::Heartbeat.started!(heartbeat_key) if heartbeat_key

    result = yield

    duration = elapsed_ms(started_at)
    Observability::Heartbeat.succeeded!(heartbeat_key, duration_ms: duration) if heartbeat_key
    Observability::Events.job_succeeded(job_key: job_key, duration_ms: duration)
    result
  rescue StandardError => e
    duration = elapsed_ms(started_at)
    Observability::Heartbeat.failed!(heartbeat_key, error_code: e.class.name, duration_ms: duration) if heartbeat_key
    Observability::Events.job_failed(job_key: job_key, error_code: e.class.name, duration_ms: duration)
    # Jobs previously failed into Rails.logger only; surface them properly.
    Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
    raise
  ensure
    Observability::Context.reset
  end

  private

  def setup_context
    Observability::Context.reset
    Observability::Context.source = "job"
    Observability::Context.job_key = job_key
    Observability::Context.environment = Rails.env.to_s
    Observability::Context.request_id = observability_request_id.presence || "job-#{job_id}"
    Observability::Context.trace_id = Observability::Context.request_id
    Observability::Context.started_at = Time.current
  rescue StandardError => e
    Rails.logger.warn("[observability] job context failed: #{e.class}")
  end

  def elapsed_ms(started_at)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end
end
