require "rails_helper"

RSpec.describe Observability::Heartbeat do
  describe ".started! / .succeeded! / .failed!" do
    it "registers a heartbeat on first use" do
      expect { described_class.started!("relationship_daily_job") }
        .to change(ObservabilityHeartbeat, :count).by(1)

      record = ObservabilityHeartbeat.find_by(key: "relationship_daily_job")
      expect(record.category).to eq("job")
      expect(record.expected_interval_seconds).to eq(1.day.to_i)
      expect(record.last_started_at).to be_present
    end

    it "clears the failure streak on success" do
      described_class.failed!("push_dispatch", error_code: "ArgumentError")
      described_class.failed!("push_dispatch", error_code: "ArgumentError")
      expect(ObservabilityHeartbeat.find_by(key: "push_dispatch").consecutive_failures).to eq(2)

      described_class.succeeded!("push_dispatch", duration_ms: 120)

      record = ObservabilityHeartbeat.find_by(key: "push_dispatch")
      expect(record.consecutive_failures).to eq(0)
      expect(record.last_error_code).to be_nil
      expect(record.last_duration_ms).to eq(120)
    end

    it "stores only the error class, never a message that could carry PII" do
      described_class.failed!("push_dispatch", error_code: "boom for user someone@example.com")

      record = ObservabilityHeartbeat.find_by(key: "push_dispatch")
      expect(record.last_error_code).not_to include("@")
      expect(record.last_error_code).not_to include(" ")
    end
  end

  describe ".track" do
    it "records success and returns the block value" do
      result = described_class.track("push_dispatch") { :done }

      expect(result).to eq(:done)
      expect(ObservabilityHeartbeat.find_by(key: "push_dispatch").last_succeeded_at).to be_present
    end

    it "records the failure and re-raises the original exception untouched" do
      expect { described_class.track("push_dispatch") { raise ArgumentError, "boom" } }
        .to raise_error(ArgumentError, "boom")

      record = ObservabilityHeartbeat.find_by(key: "push_dispatch")
      expect(record.consecutive_failures).to eq(1)
      expect(record.last_error_code).to eq("ArgumentError")
    end
  end

  describe "never breaking the caller" do
    it "swallows a database failure" do
      allow(ObservabilityHeartbeat).to receive(:by_key).and_raise(ActiveRecord::StatementInvalid, "boom")

      expect { described_class.succeeded!("push_dispatch") }.not_to raise_error
    end
  end

  describe "staleness" do
    let(:heartbeat) do
      ObservabilityHeartbeat.create!(key: "custom", category: "cron", expected_interval_seconds: 3600)
    end

    it "is healthy inside the expected interval" do
      heartbeat.update!(last_succeeded_at: 30.minutes.ago)

      expect(heartbeat.status).to eq(ObservabilityHeartbeat::STATUS_HEALTHY)
      expect(heartbeat).not_to be_stale
    end

    it "warns past 1.5x the interval" do
      heartbeat.update!(last_succeeded_at: 100.minutes.ago)

      expect(heartbeat.status).to eq(ObservabilityHeartbeat::STATUS_WARNING)
    end

    it "is critical past 2x the interval" do
      heartbeat.update!(last_succeeded_at: 3.hours.ago)

      expect(heartbeat.status).to eq(ObservabilityHeartbeat::STATUS_CRITICAL)
    end

    it "reports insufficient_data — not critical — for a freshly registered process" do
      # Otherwise every deploy would light up the whole board with heartbeats
      # that simply have not had their first scheduled run yet.
      expect(heartbeat.status).to eq(ObservabilityHeartbeat::STATUS_PENDING)
      expect(heartbeat.seconds_since_success).to be_nil
    end

    it "becomes critical once a never-succeeded process outlives its first interval" do
      heartbeat.update!(created_at: 3.hours.ago)

      expect(heartbeat.status).to eq(ObservabilityHeartbeat::STATUS_CRITICAL)
    end
  end
end
