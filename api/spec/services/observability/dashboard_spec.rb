require "rails_helper"

RSpec.describe Observability::Dashboard do
  LegacyResult = Struct.new(
    :check_key,
    :status,
    :current_value,
    :reference_value,
    :threshold_value,
    :sample_size,
    :dimensions,
    :explanation,
    :window_started_at,
    :window_ended_at,
    :checked_at,
    keyword_init: true
  )

  def legacy_result(check_key:, current_value:)
    now = Time.current

    LegacyResult.new(
      check_key: check_key,
      status: Observability::CheckResult::HEALTHY,
      current_value: current_value,
      reference_value: nil,
      threshold_value: nil,
      sample_size: 10,
      dimensions: {},
      explanation: "ok",
      window_started_at: now - 15.minutes,
      window_ended_at: now,
      checked_at: now
    )
  end

  it "infers units and tolerates missing legacy metadata attributes" do
    allow(ObservabilityCheckResult).to receive(:latest_per_check).and_return([
      legacy_result(check_key: "api_latency_p95", current_value: 1.23),
      legacy_result(check_key: "google_auth_consent_anomaly", current_value: 2),
      legacy_result(check_key: "android_registration_conversion", current_value: 0.8)
    ])

    payload = described_class.new.call

    expect(payload[:cards][:api_infrastructure]).to include(unit: "seconds", headline: "1.23s", definition: nil)
    expect(payload[:cards][:google_auth]).to include(unit: "count", headline: "2", definition: nil)
    expect(payload[:cards][:android_registration]).to include(unit: "ratio", headline: "80,0%", definition: nil)
  end
end
