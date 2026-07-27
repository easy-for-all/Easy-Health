class ApplicationJob < ActiveJob::Base
  # Correlation context, job_* structured events and (opt-in) heartbeats.
  # See app/jobs/concerns/observability_instrumented.rb.
  include ObservabilityInstrumented

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
