module Analytics
  # Standardized metric payload for the Admin dashboard. A metric is NEVER just
  # a percentage — it always carries its numerator, denominator, sample size and
  # a status so the UI can show "insufficient sample" / "cohort not mature"
  # instead of a misleading 0% or a negative drop-off.
  #
  #   MetricResult.ratio(numerator: 21, denominator: 360, definition: "first_workout_conversion_v1")
  #     => { value: 5.8, numerator: 21, denominator: 360, sample_size: 360,
  #          status: "complete", cohort_maturity: "mature",
  #          definition: "first_workout_conversion_v1" }
  class MetricResult
    STATUSES = %w[complete incomplete insufficient_sample inconsistent no_coverage].freeze

    MIN_SAMPLE = Integer(ENV.fetch("ANALYTICS_MIN_SAMPLE", 5))

    attr_reader :numerator, :denominator, :definition, :cohort_maturity, :note

    def initialize(numerator:, denominator:, definition:, cohort_maturity: "mature", note: nil, status: nil)
      @numerator = numerator.to_i
      @denominator = denominator.to_i
      @definition = definition
      @cohort_maturity = cohort_maturity
      @note = note
      @forced_status = status
    end

    def self.ratio(numerator:, denominator:, definition:, **opts)
      new(numerator: numerator, denominator: denominator, definition: definition, **opts)
    end

    # A raw count (no denominator) — still carries a definition + sample.
    def self.count(value, definition:, **opts)
      new(numerator: value, denominator: value, definition: definition, **opts)
    end

    def value
      return 0.0 if denominator.zero?

      # Clamp to [0, 100]: instrumentation gaps must never surface as a negative
      # drop-off or a >100% conversion.
      pct = (numerator.to_f / denominator * 100).round(1)
      pct.clamp(0.0, 100.0)
    end

    def status
      return @forced_status if @forced_status
      return "no_coverage" if denominator.zero?
      return "insufficient_sample" if denominator < MIN_SAMPLE
      return "inconsistent" if numerator > denominator

      "complete"
    end

    def as_json(*)
      {
        value: value,
        numerator: numerator,
        denominator: denominator,
        sample_size: denominator,
        status: status,
        cohort_maturity: cohort_maturity,
        definition: definition,
        note: note
      }.compact
    end
  end
end
