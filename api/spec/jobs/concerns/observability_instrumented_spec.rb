require "rails_helper"

RSpec.describe ObservabilityInstrumented do
  # A scheduled job needs its counters on the heartbeat, but writing them with a
  # second succeeded! call would record ONE execution as TWO lifecycles and
  # corrupt every "last success" reading in the admin. The concern carries the
  # metadata instead.
  let(:job_class) do
    Class.new(ApplicationJob) do
      def self.observability_heartbeat_key = "spec_instrumented_job"
      def self.name = "SpecInstrumentedJob"

      attr_reader :heartbeat_metadata

      def perform
        @heartbeat_metadata = { candidates_found: 2, events_created: 1 }
      end
    end
  end

  let(:failing_job_class) do
    Class.new(ApplicationJob) do
      def self.observability_heartbeat_key = "spec_instrumented_job"
      def self.name = "SpecFailingJob"

      def perform = raise(StandardError, "boom")
    end
  end

  it "records exactly one success per execution" do
    expect(Observability::Heartbeat).to receive(:started!).once.and_call_original
    expect(Observability::Heartbeat).to receive(:succeeded!).once.and_call_original

    job_class.perform_now
  end

  it "attaches the job's counters to that single heartbeat" do
    job_class.perform_now

    record = ObservabilityHeartbeat.by_key("spec_instrumented_job").first
    expect(record.metadata).to include("candidates_found" => 2, "events_created" => 1)
    expect(record.last_succeeded_at).to be_present
  end

  it "records a failure instead of a success and re-raises" do
    expect(Observability::Heartbeat).not_to receive(:succeeded!)

    expect { failing_job_class.perform_now }.to raise_error(StandardError, "boom")

    record = ObservabilityHeartbeat.by_key("spec_instrumented_job").first
    expect(record.last_failed_at).to be_present
    expect(record.consecutive_failures).to eq(1)
  end

  it "leaves jobs without a heartbeat key untouched" do
    plain = Class.new(ApplicationJob) do
      def self.name = "SpecPlainJob"
      def perform = :ok
    end

    expect(Observability::Heartbeat).not_to receive(:succeeded!)
    plain.perform_now
  end
end
