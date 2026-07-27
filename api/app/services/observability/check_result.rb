module Observability
  # What every check returns.
  #
  # Deliberately mirrors the discipline of Analytics::MetricResult (which the
  # admin analytics already uses): never a bare number. A value always travels
  # with the sample it came from, the threshold it was judged against and a
  # sentence explaining the verdict, so the panel can refuse to render a
  # percentage it cannot stand behind.
  #
  # THE INVARIANT: below the sample floor, status is `insufficient_data` and
  # `current_value` is nil. Not zero. "0% of registrations converted" and "we
  # could not measure conversion" are different claims, and only one of them is
  # true when nobody installed the app in the last six hours.
  class CheckResult
    HEALTHY = ObservabilityCheckResult::STATUS_HEALTHY
    WARNING = ObservabilityCheckResult::STATUS_WARNING
    CRITICAL = ObservabilityCheckResult::STATUS_CRITICAL
    INSUFFICIENT = ObservabilityCheckResult::STATUS_INSUFFICIENT

    # Worst-first, for rolling many results into one card status.
    SEVERITY_ORDER = [ CRITICAL, WARNING, HEALTHY, INSUFFICIENT ].freeze

    attr_reader :check_key, :status, :severity, :current_value, :reference_value,
                :threshold_value, :sample_size, :dimensions, :explanation,
                :definition, :window_started_at, :window_ended_at, :unit

    def initialize(check_key:, status:, current_value: nil, reference_value: nil,
                   threshold_value: nil, sample_size: nil, dimensions: {},
                   explanation: nil, definition: nil, window_started_at: nil,
                   window_ended_at: nil, unit: nil, severity: nil)
      @check_key = check_key.to_s
      @status = status.to_s
      @severity = severity&.to_s || severity_for(@status)
      # Enforced here, not trusted from callers: a check that computes 0.0 from
      # an empty denominator cannot smuggle it past this constructor.
      @current_value = @status == INSUFFICIENT ? nil : current_value
      @reference_value = reference_value
      @threshold_value = threshold_value
      @sample_size = sample_size
      @dimensions = (dimensions || {}).transform_keys(&:to_s)
      @explanation = explanation
      @definition = definition
      @window_started_at = window_started_at
      @window_ended_at = window_ended_at
      @unit = unit || "ratio"
    end

    def alerting?
      status == WARNING || status == CRITICAL
    end

    def healthy?
      status == HEALTHY
    end

    def insufficient?
      status == INSUFFICIENT
    end

    def to_h
      {
        check_key: check_key,
        status: status,
        severity: severity,
        current_value: current_value&.to_f,
        reference_value: reference_value&.to_f,
        threshold_value: threshold_value&.to_f,
        sample_size: sample_size,
        unit: unit,
        dimensions: dimensions,
        explanation: explanation,
        definition: definition,
        window_started_at: window_started_at,
        window_ended_at: window_ended_at
      }
    end

    def persist!(checked_at: Time.current)
      ObservabilityCheckResult.create!(
        check_key: check_key,
        status: status,
        severity: severity,
        environment: Rails.env.to_s,
        window_started_at: window_started_at,
        window_ended_at: window_ended_at,
        current_value: current_value,
        reference_value: reference_value,
        threshold_value: threshold_value,
        sample_size: sample_size,
        unit: unit,
        dimensions: dimensions,
        explanation: explanation,
        definition: definition,
        checked_at: checked_at
      )
    rescue StandardError => e
      Rails.logger.warn("[observability] persisting #{check_key} failed: #{e.class}")
      nil
    end

    # Worst status across a set — used to roll sub-checks into a card.
    # insufficient_data only wins when there is nothing else to report, so one
    # unmeasurable cohort cannot grey out a card that has real problems in it.
    def self.worst_status(statuses)
      present = Array(statuses).compact
      return INSUFFICIENT if present.empty?

      SEVERITY_ORDER.find { |candidate| present.include?(candidate) } || INSUFFICIENT
    end

    private

    def severity_for(status)
      case status
      when CRITICAL then "critical"
      when WARNING then "warning"
      else "info"
      end
    end
  end
end
