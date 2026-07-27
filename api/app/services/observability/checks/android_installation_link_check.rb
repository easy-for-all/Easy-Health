module Observability
  module Checks
    # PRIORITY 2 — "installs that should be linked are still anonymous".
    #
    # Two results, and the second is the valuable one:
    #
    #   android_installation_link_rate        — a rate, needs a sample
    #   authenticated_without_installation_link — a contradiction, needs none
    #
    # The denominator is first_authenticated_request_at. It is stamped before
    # the link attempt, so a failed or conflicted link remains visible instead
    # of disappearing from the measurement.
    class AndroidInstallationLinkCheck < BaseCheck
      CHECK_KEY = "android_installation_link_rate".freeze
      ORPHAN_KEY = "authenticated_without_installation_link".freeze

      DEFINITION = "instalações Android com linked_at ÷ instalações Android observadas em requisição autenticada, últimas 24h".freeze
      ORPHAN_DEFINITION = "instalações com first_authenticated_request_at preenchido e linked_at nulo após a tolerância".freeze

      def self.check_key = CHECK_KEY

      def call
        @window_started_at = now - 24.hours
        @window_ended_at = now

        link_rate_results + [ orphan_result ]
      end

      private

      def link_rate_results
        scope = AppInstallation
                .where(platform: "android", first_authenticated_request_at: @window_started_at..@window_ended_at)

        total = scope.count
        return [ no_traffic_result ] if total.zero?

        [ evaluate(total, scope.where.not(linked_at: nil).count) ]
      end

      def evaluate(total, linked)
        min_sample = config.min_android_sample

        if total < min_sample
          return insufficient(
            CHECK_KEY,
            sample_size: total,
            definition: DEFINITION,
            explanation: "Apenas #{total} instalação(ões) Android observada(s) em requisição autenticada nas últimas 24h — " \
                         "abaixo do mínimo de #{min_sample}."
          )
        end

        rate = ratio(linked, total)

        status, threshold, reason =
          if rate < config.android_link_critical_rate
            [ Observability::CheckResult::CRITICAL, config.android_link_critical_rate,
              "Apenas #{percent(rate)} das instalações Android observadas em requisição autenticada estão vinculadas " \
              "(#{linked}/#{total}), abaixo do piso crítico." ]
          elsif rate < config.android_link_warning_rate
            [ Observability::CheckResult::WARNING, config.android_link_warning_rate,
              "#{percent(rate)} das instalações Android observadas em requisição autenticada estão vinculadas " \
              "(#{linked}/#{total}), abaixo do alvo." ]
          else
            [ Observability::CheckResult::HEALTHY, config.android_link_warning_rate,
              "#{percent(rate)} das instalações Android observadas em requisição autenticada estão vinculadas (#{linked}/#{total})." ]
          end

        Observability::CheckResult.new(
          check_key: CHECK_KEY,
          status: status,
          current_value: rate,
          threshold_value: threshold,
          sample_size: total,
          explanation: reason,
          definition: DEFINITION,
          window_started_at: @window_started_at,
          window_ended_at: @window_ended_at
        )
      end

      # Deterministic: no sample floor, because this is not a measurement of a
      # population — it is a contradiction that either exists or does not.
      def orphan_result
        tolerance = config.link_tolerance_seconds
        cutoff = now - tolerance.seconds

        count = AppInstallation
                .where(platform: "android", user_id: nil, linked_at: nil)
                .where(first_authenticated_request_at: ..cutoff)
                .count

        status = count.positive? ? Observability::CheckResult::CRITICAL : Observability::CheckResult::HEALTHY

        explanation =
          if count.positive?
            "#{count} instalação(ões) observada(s) em requisição autenticada há mais de #{tolerance / 60} min continuam sem vínculo."
          else
            "Nenhuma instalação observada em requisição autenticada sem vínculo."
          end

        Observability::CheckResult.new(
          check_key: ORPHAN_KEY,
          status: status,
          current_value: count,
          threshold_value: 0,
          sample_size: count,
          unit: "count",
          explanation: explanation,
          definition: ORPHAN_DEFINITION,
          window_ended_at: now
        )
      end

      def no_traffic_result
        insufficient(
          CHECK_KEY,
          sample_size: 0,
          definition: DEFINITION,
          explanation: "Nenhuma instalação Android observada em requisição autenticada nas últimas 24h. Sem base para medir vínculo."
        )
      end
    end
  end
end
