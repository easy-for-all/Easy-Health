module Observability
  module Checks
    # PRIORITY 1 — "the build shipped and nobody signed up".
    #
    # Denominator is app_installations, not analytics events: an install row is
    # written by the app's own registration call, while analytics events are
    # consent-gated and would undercount exactly the users we are worried about.
    # Numerator is `user_id IS NOT NULL` — an install that reached an account.
    #
    # Evaluated per descriptive build cohort. Build helps answer "which release
    # changed conversion?", but it is not used as reconciliation eligibility.
    #
    # Backed by index_app_installations_on_platform_and_created_at.
    class AndroidRegistrationConversionCheck < BaseCheck
      CHECK_KEY = "android_registration_conversion".freeze
      DEFINITION = "instalações Android com usuário vinculado ÷ instalações Android criadas na janela, por coorte descritiva de build".freeze

      BASELINE_DAYS = 7

      def self.check_key = CHECK_KEY

      def call
        window_start = now - 24.hours
        @window_started_at = window_start
        @window_ended_at = now

        current = conversion_by_group(window_start, now)
        baseline = conversion_by_group(now - BASELINE_DAYS.days - 24.hours, window_start)

        return [ no_traffic_result ] if current.values.sum { |row| row[:total] }.zero?

        current.map { |group, row| evaluate(group, row, baseline[group]) }
      end

      private

      # One grouped query per window. `installations` is the denominator,
      # `linked` the numerator.
      def conversion_by_group(from, to)
        rows = AppInstallation
               .where(platform: "android", created_at: from...to)
               .group(Arel.sql(Observability::BuildGroup.sql))
               .pluck(
                 Arel.sql(Observability::BuildGroup.sql),
                 Arel.sql("COUNT(*)"),
                 Arel.sql("COUNT(*) FILTER (WHERE user_id IS NOT NULL)")
               )

        rows.each_with_object(Hash.new { |h, k| h[k] = { total: 0, linked: 0 } }) do |(group, total, linked), acc|
          acc[group] = { total: total.to_i, linked: linked.to_i }
        end
      end

      def evaluate(group, row, baseline_row)
        total = row[:total]
        min_sample = config.min_android_sample

        if total < min_sample
          return insufficient(
            CHECK_KEY,
            sample_size: total,
            dimensions: { "build_group" => group },
            definition: DEFINITION,
            explanation: "Apenas #{total} instalação(ões) na coorte '#{group}' nas últimas 24h — " \
                         "abaixo do mínimo de #{min_sample}. Sem base para afirmar conversão."
          )
        end

        rate = ratio(row[:linked], total)
        baseline_rate = baseline_row && baseline_row[:total] >= min_sample ? ratio(baseline_row[:linked], baseline_row[:total]) : nil
        drop = relative_drop(rate, baseline_rate)

        status, threshold, reason = classify(rate, drop, group)

        Observability::CheckResult.new(
          check_key: CHECK_KEY,
          status: status,
          current_value: rate,
          reference_value: baseline_rate,
          threshold_value: threshold,
          sample_size: total,
          dimensions: { "build_group" => group },
          explanation: reason,
          definition: DEFINITION,
          window_started_at: @window_started_at,
          window_ended_at: @window_ended_at
        )
      end

      # Two independent triggers: an absolute floor (this is bad in any world)
      # and a relative drop against the trailing baseline (this got worse than
      # it used to be). Either one is enough.
      def classify(rate, drop, group)
        if rate < config.android_registration_critical_rate
          [ Observability::CheckResult::CRITICAL, config.android_registration_critical_rate,
            "Conversão de #{percent(rate)} na coorte '#{group}', abaixo do piso crítico de " \
            "#{percent(config.android_registration_critical_rate)}." ]
        elsif drop && drop >= config.android_registration_critical_drop
          [ Observability::CheckResult::CRITICAL, config.android_registration_critical_drop,
            "Conversão caiu #{percent(drop)} contra a linha de base de 7 dias na coorte '#{group}'." ]
        elsif rate < config.android_registration_warning_rate
          [ Observability::CheckResult::WARNING, config.android_registration_warning_rate,
            "Conversão de #{percent(rate)} na coorte '#{group}', abaixo do alvo de " \
            "#{percent(config.android_registration_warning_rate)}." ]
        elsif drop && drop >= config.android_registration_warning_drop
          [ Observability::CheckResult::WARNING, config.android_registration_warning_drop,
            "Conversão caiu #{percent(drop)} contra a linha de base de 7 dias na coorte '#{group}'." ]
        else
          [ Observability::CheckResult::HEALTHY, config.android_registration_warning_rate,
            "Conversão de #{percent(rate)} na coorte '#{group}', dentro do esperado." ]
        end
      end

      # Zero installs is not zero conversion. Reported as unmeasurable so the
      # card greys out instead of turning red on a quiet night.
      def no_traffic_result
        insufficient(
          CHECK_KEY,
          sample_size: 0,
          definition: DEFINITION,
          explanation: "Nenhuma instalação Android registrada nas últimas 24h. Sem base para medir conversão."
        )
      end
    end
  end
end
