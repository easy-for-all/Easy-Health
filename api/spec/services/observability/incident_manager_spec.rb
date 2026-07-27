require "rails_helper"

RSpec.describe Observability::IncidentManager do
  def result(status:, check_key: "android_registration_conversion", dimensions: { "build_group" => "current" }, value: 0.1)
    Observability::CheckResult.new(
      check_key: check_key,
      status: status,
      current_value: value,
      threshold_value: 0.3,
      sample_size: 50,
      dimensions: dimensions,
      explanation: "explicação"
    )
  end

  describe "opening" do
    it "opens an incident for an alerting result" do
      expect { described_class.reconcile(result(status: "warning")) }
        .to change(ObservabilityIncident, :count).by(1)

      incident = ObservabilityIncident.last
      expect(incident.status).to eq("open")
      expect(incident.severity).to eq("warning")
      expect(incident.occurrence_count).to eq(1)
      expect(incident.source).to eq("internal_check")
    end

    it "does not open an incident for a healthy result" do
      expect { described_class.reconcile(result(status: "healthy")) }
        .not_to change(ObservabilityIncident, :count)
    end

    it "does not open an incident for insufficient_data" do
      # We could not measure, so we can claim neither a problem nor recovery.
      expect { described_class.reconcile(result(status: "insufficient_data")) }
        .not_to change(ObservabilityIncident, :count)
    end
  end

  describe "deduplication" do
    it "collapses repeated detections into one incident" do
      3.times { described_class.reconcile(result(status: "warning")) }

      expect(ObservabilityIncident.count).to eq(1)
      expect(ObservabilityIncident.last.occurrence_count).to eq(3)
    end

    it "keeps separate incidents for different dimensions" do
      described_class.reconcile(result(status: "warning", dimensions: { "build_group" => "current" }))
      described_class.reconcile(result(status: "warning", dimensions: { "build_group" => "reported" }))

      expect(ObservabilityIncident.count).to eq(2)
    end

    it "ignores dimensions outside the allow-list when identifying an incident" do
      # A user or installation ref in the fingerprint would mint one incident
      # per affected user and make the panel unusable.
      described_class.reconcile(result(status: "warning", dimensions: { "build_group" => "current", "user_id" => 1 }))
      described_class.reconcile(result(status: "warning", dimensions: { "build_group" => "current", "user_id" => 2 }))

      expect(ObservabilityIncident.count).to eq(1)
      expect(ObservabilityIncident.last.dimensions).not_to have_key("user_id")
    end

    it "escalates severity in place rather than opening a second incident" do
      described_class.reconcile(result(status: "warning"))
      described_class.reconcile(result(status: "critical"))

      expect(ObservabilityIncident.count).to eq(1)
      expect(ObservabilityIncident.last.severity).to eq("critical")
    end
  end

  describe "resolution" do
    it "auto-resolves when the check recovers" do
      described_class.reconcile(result(status: "critical"))
      described_class.reconcile(result(status: "healthy"))

      incident = ObservabilityIncident.last
      expect(incident.status).to eq("resolved")
      expect(incident.resolved_at).to be_present
    end

    it "does NOT resolve on insufficient_data" do
      described_class.reconcile(result(status: "critical"))
      described_class.reconcile(result(status: "insufficient_data"))

      expect(ObservabilityIncident.last.status).to eq("open")
    end

    it "opens a fresh incident when the same problem recurs after resolution" do
      described_class.reconcile(result(status: "warning"))
      described_class.reconcile(result(status: "healthy"))
      described_class.reconcile(result(status: "warning"))

      expect(ObservabilityIncident.count).to eq(2)
      expect(ObservabilityIncident.active.count).to eq(1)
    end
  end

  describe "acknowledgement" do
    it "records who acknowledged without changing the active state" do
      described_class.reconcile(result(status: "warning"))
      incident = ObservabilityIncident.last

      described_class.acknowledge!(incident, acknowledged_by: "admin:7")

      expect(incident.reload.status).to eq("acknowledged")
      expect(incident.acknowledged_by).to eq("admin:7")
      expect(incident).to be_active
    end
  end

  describe "alert cooldown" do
    around do |example|
      with_env("OBSERVABILITY_ALERTS_ENABLED" => "true",
               "OBSERVABILITY_ALERT_WEBHOOK_URL" => "https://example.test/hook",
               "OBSERVABILITY_ALERT_COOLDOWN_MINUTES" => "60") { example.run }
    end

    before { allow(Observability::Notifier).to receive(:deliver).and_return(true) }

    it "notifies once on open and then suppresses recurrences within the cooldown" do
      described_class.reconcile(result(status: "warning"))
      described_class.reconcile(result(status: "warning"))
      described_class.reconcile(result(status: "warning"))

      expect(Observability::Notifier).to have_received(:deliver).once
      expect(ObservabilityIncident.last.notification_count).to eq(1)
    end

    it "notifies again once the cooldown has elapsed" do
      described_class.reconcile(result(status: "warning"))
      ObservabilityIncident.last.update!(last_notified_at: 2.hours.ago)

      described_class.reconcile(result(status: "warning"))

      expect(Observability::Notifier).to have_received(:deliver).twice
    end

    it "bypasses the cooldown for an escalation" do
      described_class.reconcile(result(status: "warning"))
      described_class.reconcile(result(status: "critical"))

      expect(Observability::Notifier).to have_received(:deliver).twice
    end

    it "bypasses the cooldown for a resolution" do
      described_class.reconcile(result(status: "warning"))
      described_class.reconcile(result(status: "healthy"))

      expect(Observability::Notifier).to have_received(:deliver).twice
    end
  end

  describe "alerts disabled by default" do
    it "does not deliver anything when OBSERVABILITY_ALERTS_ENABLED is off" do
      with_env("OBSERVABILITY_ALERTS_ENABLED" => "false") do
        expect(Observability::Notifier.deliver(incident: ObservabilityIncident.new, event: "x")).to be(false)
      end
    end
  end
end
