module Observability
  module Checks
    # PRIORITY 3 — "Google login started failing".
    #
    # Reads the google_auth_* events emitted by Observability::Events, using the
    # existing (event_name, occurred_at) index on product_analytics_events.
    #
    # SPLIT BY FLOW, ALWAYS. Native and web are different code paths with
    # different failure modes (a wrong Android client id breaks native only),
    # and a blended error rate hides a total native outage behind healthy web
    # traffic. That split is the reason this check exists at all.
    #
    # Second result — consent anomaly. `consent_required` is not inherently a
    # bug: signing in to an account that does not exist yet legitimately returns
    # it. It IS a bug when the client already collected consent
    # (auth_intent=sign_up AND terms_accepted=true) and the server still refused.
    # Only the second case is alerted on.
    class GoogleAuthHealthCheck < BaseCheck
      CHECK_KEY = "google_auth_error_rate".freeze
      CONSENT_KEY = "google_auth_consent_anomaly".freeze

      DEFINITION = "google_auth_failed ÷ (google_auth_succeeded + google_auth_failed), por fluxo".freeze
      CONSENT_DEFINITION = "falhas consent_required em tentativas de cadastro que já traziam os termos aceitos".freeze

      EVENT_NAMES = %w[google_auth_succeeded google_auth_failed].freeze

      def self.check_key = CHECK_KEY

      def call
        @window_started_at = now - config.google_auth_window_minutes.minutes
        @window_ended_at = now

        rows = fetch_rows
        return [ no_traffic_result, consent_result(rows) ] if rows.empty?

        by_flow = rows.group_by { |row| row[:flow] }
        by_flow.map { |flow, flow_rows| evaluate(flow, flow_rows) } + [ consent_result(rows) ]
      end

      private

      def fetch_rows
        ProductAnalyticsEvent
          .where(event_name: EVENT_NAMES, occurred_at: @window_started_at..@window_ended_at)
          .group(
            :event_name,
            Arel.sql("properties->>'auth_flow'"),
            Arel.sql("properties->>'error_code'"),
            Arel.sql("properties->>'auth_intent'"),
            Arel.sql("properties->>'terms_accepted'")
          )
          .pluck(
            :event_name,
            Arel.sql("properties->>'auth_flow'"),
            Arel.sql("properties->>'error_code'"),
            Arel.sql("properties->>'auth_intent'"),
            Arel.sql("properties->>'terms_accepted'"),
            Arel.sql("COUNT(*)")
          )
          .map do |event_name, flow, error_code, intent, terms, count|
            {
              event_name: event_name,
              flow: flow.presence || "unknown",
              error_code: error_code.presence,
              intent: intent.presence || "unknown",
              terms_accepted: terms.to_s == "true",
              count: count.to_i
            }
          end
      end

      def evaluate(flow, rows)
        successes = rows.select { |r| r[:event_name] == "google_auth_succeeded" }.sum { |r| r[:count] }
        failures  = rows.select { |r| r[:event_name] == "google_auth_failed" }.sum { |r| r[:count] }
        attempts  = successes + failures
        min_sample = config.min_google_auth_sample

        if attempts < min_sample
          return insufficient(
            CHECK_KEY,
            sample_size: attempts,
            dimensions: { "auth_flow" => flow },
            definition: DEFINITION,
            explanation: "Apenas #{attempts} tentativa(s) no fluxo '#{flow}' na janela de " \
                         "#{config.google_auth_window_minutes} min — abaixo do mínimo de #{min_sample}."
          )
        end

        rate = ratio(failures, attempts)
        top_error = top_error_code(rows)

        status, threshold =
          if rate > config.google_auth_critical_error_rate
            [ Observability::CheckResult::CRITICAL, config.google_auth_critical_error_rate ]
          elsif rate > config.google_auth_warning_error_rate
            [ Observability::CheckResult::WARNING, config.google_auth_warning_error_rate ]
          else
            [ Observability::CheckResult::HEALTHY, config.google_auth_warning_error_rate ]
          end

        explanation = "#{percent(rate)} de falhas no fluxo '#{flow}' (#{failures}/#{attempts})"
        explanation += ", principal código: #{top_error}" if top_error
        explanation += "."

        Observability::CheckResult.new(
          check_key: CHECK_KEY,
          status: status,
          current_value: rate,
          threshold_value: threshold,
          sample_size: attempts,
          dimensions: { "auth_flow" => flow, "top_error_code" => top_error }.compact,
          explanation: explanation,
          definition: DEFINITION,
          window_started_at: @window_started_at,
          window_ended_at: @window_ended_at
        )
      end

      # The anomaly: consent was collected AND the server refused for missing
      # consent. Any occurrence is a defect, so this does not wait for a sample.
      def consent_result(rows)
        anomalous = rows.select do |row|
          row[:event_name] == "google_auth_failed" &&
            row[:error_code] == "consent_required" &&
            row[:intent] == "sign_up" &&
            row[:terms_accepted]
        end
        count = anomalous.sum { |row| row[:count] }

        expected = rows.select do |row|
          row[:event_name] == "google_auth_failed" && row[:error_code] == "consent_required"
        end.sum { |row| row[:count] } - count

        status = count.positive? ? Observability::CheckResult::CRITICAL : Observability::CheckResult::HEALTHY

        explanation =
          if count.positive?
            "#{count} cadastro(s) com termos aceitos receberam consent_required — o consentimento foi " \
            "coletado e mesmo assim recusado."
          else
            "Nenhuma anomalia de consentimento. (#{expected} consent_required esperado(s) em login de conta inexistente.)"
          end

        Observability::CheckResult.new(
          check_key: CONSENT_KEY,
          status: status,
          current_value: count,
          threshold_value: 0,
          sample_size: count + expected,
          unit: "count",
          dimensions: { "expected_consent_required" => expected },
          explanation: explanation,
          definition: CONSENT_DEFINITION,
          window_started_at: @window_started_at,
          window_ended_at: @window_ended_at
        )
      end

      def top_error_code(rows)
        rows
          .select { |r| r[:event_name] == "google_auth_failed" && r[:error_code].present? }
          .group_by { |r| r[:error_code] }
          .transform_values { |group| group.sum { |r| r[:count] } }
          .max_by { |_code, count| count }
          &.first
      end

      def no_traffic_result
        insufficient(
          CHECK_KEY,
          sample_size: 0,
          definition: DEFINITION,
          explanation: "Nenhuma tentativa de login Google na janela de #{config.google_auth_window_minutes} min."
        )
      end
    end
  end
end
