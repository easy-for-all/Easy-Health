module Observability
  # Rolling, in-process aggregate of HTTP outcomes: error rate and p95 latency.
  #
  # Why in-process and not a table: this is written on the hottest path in the
  # app. Persisting a row per request would turn observability into the
  # performance problem it is meant to detect. Why not a metrics gem: none is
  # installed yet, and card 1 needs *some* honest signal today.
  #
  # Limits, stated plainly so nobody reads more into the number than it holds:
  #   * It only knows about the currently running Puma process. config/puma.rb
  #     declares no `workers`, so today that is the whole API — the moment a
  #     `workers` line appears, this becomes one worker's view.
  #   * It resets on restart/deploy.
  #   * It covers WINDOW_MINUTES only.
  # The admin payload reports `source: "in_process"` and falls back to
  # insufficient_data below the sample floor rather than implying a green zero.
  module HttpStats
    WINDOW_MINUTES = 15
    BUCKET_SECONDS = 60
    BUCKETS = WINDOW_MINUTES * 60 / BUCKET_SECONDS

    # Latency is kept as a bounded histogram rather than raw samples so memory
    # is constant regardless of traffic. p95 is interpolated from the buckets.
    LATENCY_BUCKETS_MS = [ 10, 25, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000, 30_000 ].freeze

    MUTEX = Mutex.new

    module_function

    def record(status:, duration_ms:)
      return unless Observability::Config.enabled?

      code = status.to_i
      bucket_key = current_bucket

      MUTEX.synchronize do
        bucket = bucket_for(bucket_key)
        bucket[:total] += 1
        bucket[:server_errors] += 1 if code >= 500
        bucket[:client_errors] += 1 if code >= 400 && code < 500
        bucket[:latency][latency_index(duration_ms)] += 1
        prune(bucket_key)
      end
      nil
    rescue StandardError => e
      Rails.logger.warn("[observability] http_stats record failed: #{e.class}")
      nil
    end

    # @return [Hash] total, server_errors, error_rate (nil when no sample),
    #   p95_seconds (nil when no sample), window_seconds, source
    def snapshot
      cutoff = current_bucket - BUCKETS + 1

      totals = { total: 0, server_errors: 0, client_errors: 0 }
      latency = Array.new(LATENCY_BUCKETS_MS.length + 1, 0)

      MUTEX.synchronize do
        store.each do |key, bucket|
          next if key < cutoff

          totals[:total] += bucket[:total]
          totals[:server_errors] += bucket[:server_errors]
          totals[:client_errors] += bucket[:client_errors]
          bucket[:latency].each_with_index { |count, i| latency[i] += count }
        end
      end

      total = totals[:total]
      {
        total: total,
        server_errors: totals[:server_errors],
        client_errors: totals[:client_errors],
        # nil, never 0.0, when there is nothing to divide by.
        error_rate: total.positive? ? (totals[:server_errors].to_f / total) : nil,
        p95_seconds: percentile_seconds(latency, total, 0.95),
        window_seconds: WINDOW_MINUTES * 60,
        source: "in_process"
      }
    rescue StandardError => e
      Rails.logger.warn("[observability] http_stats snapshot failed: #{e.class}")
      { total: 0, server_errors: 0, client_errors: 0, error_rate: nil,
        p95_seconds: nil, window_seconds: WINDOW_MINUTES * 60, source: "in_process" }
    end

    def reset!
      MUTEX.synchronize { @store = nil }
    end

    # ── internals ────────────────────────────────────────────────────────────

    def store
      @store ||= {}
    end

    def bucket_for(key)
      store[key] ||= {
        total: 0,
        server_errors: 0,
        client_errors: 0,
        latency: Array.new(LATENCY_BUCKETS_MS.length + 1, 0)
      }
    end

    def prune(current_key)
      cutoff = current_key - BUCKETS + 1
      store.delete_if { |key, _| key < cutoff }
    end

    def current_bucket
      (Process.clock_gettime(Process::CLOCK_MONOTONIC) / BUCKET_SECONDS).floor
    end

    def latency_index(duration_ms)
      value = duration_ms.to_f
      idx = LATENCY_BUCKETS_MS.index { |edge| value <= edge }
      idx || LATENCY_BUCKETS_MS.length
    end

    # Upper edge of the bucket holding the requested percentile. Coarse by
    # design: it answers "is latency in the seconds range" without keeping
    # unbounded samples. Returns nil with no data rather than 0.
    def percentile_seconds(latency, total, percentile)
      return nil if total.zero?

      target = (total * percentile).ceil
      running = 0

      latency.each_with_index do |count, index|
        running += count
        next if running < target

        edge = LATENCY_BUCKETS_MS[index] || LATENCY_BUCKETS_MS.last
        return (edge / 1000.0).round(3)
      end

      (LATENCY_BUCKETS_MS.last / 1000.0).round(3)
    end
  end
end
