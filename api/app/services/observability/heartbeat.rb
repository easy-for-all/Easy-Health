module Observability
  # The only thing callers touch to report process liveness.
  #
  # Everything here is best-effort by design, following the same discipline as
  # Analytics::ServerEvents and AppInstallationReconciliation: a heartbeat is a
  # diagnostic, so a failure to record one must never take down the job it is
  # observing. Every public method swallows exceptions and warns.
  module Heartbeat
    # The processes we expect to be alive, with how often each should succeed.
    # Registered up front (rake observability:heartbeats) so a process that has
    # NEVER run is visible as missing, rather than being invisible because no
    # row exists. That absence is exactly the failure mode this layer is for.
    REGISTRY = {
      "relationship_daily_job" => { category: "job", interval: 1.day },
      "make_pending_retry" => { category: "cron", interval: 15.minutes },
      "make_webhook_delivery" => { category: "integration", interval: 1.day },
      "stripe_webhook_processing" => { category: "integration", interval: 1.day },
      "android_analytics_ingestion" => { category: "pipeline", interval: 6.hours },
      "push_dispatch" => { category: "job", interval: 1.hour },
      "observability_health_check" => { category: "cron", interval: 15.minutes },
      "bi_replica_refresh" => { category: "pipeline", interval: 1.day },
      "google_ads_acquisition_sync" => { category: "cron", interval: 1.hour },
      # Orchestration event producers. These have no other symptom when they
      # stop: no error, no queue backlog — just events that never get created,
      # which is invisible until someone asks why nobody is being reminded.
      "first_workout_not_started_2h" => { category: "cron", interval: 15.minutes },
      "first_workout_not_started_24h" => { category: "cron", interval: 15.minutes },
      "scheduled_workout_reminder" => { category: "cron", interval: 15.minutes },
      "push_dispatch_deferred" => { category: "cron", interval: 15.minutes }
    }.freeze

    module_function

    def started!(key, metadata: nil)
      record = find_or_register(key)
      return nil if record.nil?

      attrs = { last_started_at: Time.current }
      attrs[:metadata] = safe_metadata(metadata) if metadata
      record.update_columns(attrs.merge(updated_at: Time.current))
      record
    rescue StandardError => e
      warn_failure(key, "started", e)
      nil
    end

    def succeeded!(key, duration_ms: nil, metadata: nil)
      record = find_or_register(key)
      return nil if record.nil?

      now = Time.current
      attrs = {
        last_succeeded_at: now,
        consecutive_failures: 0,
        last_error_code: nil,
        updated_at: now
      }
      attrs[:last_duration_ms] = duration_ms.to_i if duration_ms
      attrs[:metadata] = safe_metadata(metadata) if metadata

      record.update_columns(attrs)
      record
    rescue StandardError => e
      warn_failure(key, "succeeded", e)
      nil
    end

    def failed!(key, error_code: nil, duration_ms: nil, metadata: nil)
      record = find_or_register(key)
      return nil if record.nil?

      now = Time.current
      attrs = {
        last_failed_at: now,
        consecutive_failures: record.consecutive_failures.to_i + 1,
        last_error_code: normalize_error_code(error_code),
        updated_at: now
      }
      attrs[:last_duration_ms] = duration_ms.to_i if duration_ms
      attrs[:metadata] = safe_metadata(metadata) if metadata

      record.update_columns(attrs)
      record
    rescue StandardError => e
      warn_failure(key, "failed", e)
      nil
    end

    # Wraps a unit of work: started! before, succeeded!/failed! after, and the
    # original exception always propagates untouched.
    def track(key, metadata: nil)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      started!(key, metadata: metadata)

      result = yield

      succeeded!(key, duration_ms: elapsed_ms(started_at))
      result
    rescue StandardError => e
      failed!(key, error_code: e.class.name, duration_ms: elapsed_ms(started_at))
      raise
    end

    def stale?(key, now: Time.current)
      record = ObservabilityHeartbeat.by_key(key).first
      return false if record.nil?

      record.stale?(now: now)
    rescue StandardError
      false
    end

    def status(key, now: Time.current)
      record = ObservabilityHeartbeat.by_key(key).first
      return nil if record.nil?

      record.status(now: now)
    rescue StandardError
      nil
    end

    # Creates every registry row that does not exist yet. Idempotent; safe to
    # run on every deploy.
    def register_all!
      REGISTRY.map { |key, _| find_or_register(key) }.compact
    end

    # ── internals ────────────────────────────────────────────────────────────

    def find_or_register(key)
      name = key.to_s
      existing = ObservabilityHeartbeat.by_key(name).first
      return existing if existing

      spec = REGISTRY[name] || { category: "job", interval: 1.day }
      ObservabilityHeartbeat.create!(
        key: name,
        category: spec[:category],
        expected_interval_seconds: spec[:interval].to_i
      )
    rescue ActiveRecord::RecordNotUnique
      # Two processes registering the same key at once — either row is correct.
      ObservabilityHeartbeat.by_key(key.to_s).first
    end

    # Error classes only, never messages: a message can carry an id, an email or
    # a token, and this value is rendered in the admin panel.
    def normalize_error_code(code)
      value = code.to_s.strip
      return nil if value.empty?

      value.gsub(/[^A-Za-z0-9_.:-]/, "_")[0, 64]
    end

    def safe_metadata(metadata)
      RelationshipEventTracker.sanitize_metadata(metadata || {})
    rescue StandardError
      {}
    end

    def elapsed_ms(started_at)
      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end

    def warn_failure(key, stage, error)
      Rails.logger.warn("[observability] heartbeat #{key} #{stage} failed: #{error.class}")
    end
  end
end
