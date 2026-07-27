module Observability
  module Checks
    # Feeds the "API & Infraestrutura" card from Observability::HttpStats.
    #
    # SCOPE, STATED HONESTLY: this only knows about the running Puma process's
    # last 15 minutes, and it resets on deploy. It is not infrastructure
    # monitoring — there is no CPU, memory, disk or container-restart signal
    # here, and there will not be until an external collector exists. What it
    # does give, today, is a real 5xx rate and a real latency band measured from
    # actual traffic, which is strictly better than the card having nothing.
    #
    # Below the sample floor it reports insufficient_data. A quiet API is not a
    # healthy API, and a green zero would be a lie.
    class ApiHealthCheck < BaseCheck
      ERROR_KEY = "api_error_rate".freeze
      LATENCY_KEY = "api_latency_p95".freeze

      def self.check_key = ERROR_KEY

      def call
        snapshot = Observability::HttpStats.snapshot
        @window_started_at = now - snapshot[:window_seconds].seconds
        @window_ended_at = now

        [ error_rate_result(snapshot), latency_result(snapshot) ]
      end

      private

      def definition
        "respostas 5xx ÷ total de respostas, agregado em memória no processo Puma (últimos 15 min, zera a cada deploy)"
      end

      def error_rate_result(snapshot)
        total = snapshot[:total].to_i
        min_sample = config.min_http_sample

        if total < min_sample
          return insufficient(
            ERROR_KEY,
            sample_size: total,
            definition: definition,
            explanation: "Apenas #{total} requisição(ões) na janela — abaixo do mínimo de #{min_sample}. " \
                         "Sem base para afirmar taxa de erro."
          )
        end

        rate = snapshot[:error_rate]

        status, threshold =
          if rate > config.http_error_critical_rate
            [ Observability::CheckResult::CRITICAL, config.http_error_critical_rate ]
          elsif rate > config.http_error_warning_rate
            [ Observability::CheckResult::WARNING, config.http_error_warning_rate ]
          else
            [ Observability::CheckResult::HEALTHY, config.http_error_warning_rate ]
          end

        Observability::CheckResult.new(
          check_key: ERROR_KEY,
          status: status,
          current_value: rate,
          threshold_value: threshold,
          sample_size: total,
          dimensions: { "source" => snapshot[:source] },
          explanation: "#{percent(rate)} de respostas 5xx (#{snapshot[:server_errors]}/#{total}) nos últimos 15 min.",
          definition: definition,
          window_started_at: @window_started_at,
          window_ended_at: @window_ended_at
        )
      end

      def latency_result(snapshot)
        total = snapshot[:total].to_i
        min_sample = config.min_http_sample
        latency_definition = "p95 aproximado de duração das respostas, por histograma em memória (últimos 15 min)"

        if total < min_sample
          return insufficient(
            LATENCY_KEY,
            sample_size: total,
            definition: latency_definition,
            explanation: "Apenas #{total} requisição(ões) na janela — abaixo do mínimo de #{min_sample}."
          )
        end

        p95 = snapshot[:p95_seconds]

        status, threshold =
          if p95 > config.http_latency_critical_seconds
            [ Observability::CheckResult::CRITICAL, config.http_latency_critical_seconds ]
          elsif p95 > config.http_latency_warning_seconds
            [ Observability::CheckResult::WARNING, config.http_latency_warning_seconds ]
          else
            [ Observability::CheckResult::HEALTHY, config.http_latency_warning_seconds ]
          end

        Observability::CheckResult.new(
          check_key: LATENCY_KEY,
          status: status,
          current_value: p95,
          threshold_value: threshold,
          sample_size: total,
          unit: "seconds",
          dimensions: { "source" => snapshot[:source] },
          # "até" because the histogram gives the bucket's upper edge, not an
          # exact quantile — better to name the imprecision than imply accuracy.
          explanation: "p95 de até #{p95}s em #{total} requisição(ões) nos últimos 15 min.",
          definition: latency_definition,
          window_started_at: @window_started_at,
          window_ended_at: @window_ended_at
        )
      end
    end
  end
end
