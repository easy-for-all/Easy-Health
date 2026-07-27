module Observability
  module Checks
    # Shared plumbing for every check.
    #
    # A check answers one question and returns one or more CheckResults. It
    # never opens an incident itself (that is IncidentManager's job) and never
    # raises out to the runner — a broken check must degrade to
    # insufficient_data, not take the other checks down with it.
    class BaseCheck
      def self.check_key
        raise NotImplementedError
      end

      def call
        raise NotImplementedError
      end

      # Runs the check with the guarantees above. Always returns an Array.
      def self.run
        Array(new.call).compact
      rescue StandardError => e
        Rails.logger.error("[observability] check #{check_key} raised: #{e.class}: #{e.message}")
        Sentry.capture_exception(e) if defined?(Sentry) && Sentry.initialized?
        [ failure_result(e) ]
      end

      def self.failure_result(error)
        Observability::CheckResult.new(
          check_key: check_key,
          status: Observability::CheckResult::INSUFFICIENT,
          explanation: "Verificação falhou ao executar (#{error.class}). Sem medição neste ciclo.",
          definition: "Erro interno do próprio check — ver Sentry."
        )
      end

      private

      def config
        Observability::Config
      end

      def now
        @now ||= Time.current
      end

      # A ratio that refuses to exist without a denominator. Every rate in this
      # layer goes through here so nothing can produce a confident 0.0 from
      # nothing.
      def ratio(numerator, denominator)
        return nil if denominator.nil? || denominator.to_i.zero?

        numerator.to_f / denominator.to_f
      end

      # Relative drop against a baseline, e.g. 0.4 == "40% worse than usual".
      # nil when there is no usable baseline to compare against.
      def relative_drop(current, baseline)
        return nil if current.nil? || baseline.nil? || baseline.to_f <= 0

        drop = (baseline.to_f - current.to_f) / baseline.to_f
        drop.negative? ? 0.0 : drop
      end

      def insufficient(check_key, sample_size:, explanation:, definition: nil, dimensions: {}, threshold_value: nil)
        Observability::CheckResult.new(
          check_key: check_key,
          status: Observability::CheckResult::INSUFFICIENT,
          sample_size: sample_size,
          dimensions: dimensions,
          explanation: explanation,
          definition: definition,
          threshold_value: threshold_value,
          window_started_at: @window_started_at,
          window_ended_at: @window_ended_at
        )
      end

      def percent(value)
        return "—" if value.nil?

        format("%.1f%%", value.to_f * 100).tr(".", ",")
      end
    end
  end
end
