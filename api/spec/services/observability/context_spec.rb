require "rails_helper"

RSpec.describe Observability::Context do
  after { described_class.reset }

  describe "identifier refs" do
    it "hashes installation and session ids instead of exposing them" do
      described_class.installation_id = "install-abc-123"
      described_class.session_id = "session-xyz-789"

      expect(described_class.installation_ref).to start_with("ins_")
      expect(described_class.session_ref).to start_with("ses_")
      expect(described_class.installation_ref).not_to include("install-abc-123")
      expect(described_class.session_ref).not_to include("session-xyz-789")
    end

    it "produces a stable ref for the same identifier" do
      described_class.installation_id = "install-abc-123"
      first = described_class.installation_ref

      described_class.reset
      described_class.installation_id = "install-abc-123"

      expect(described_class.installation_ref).to eq(first)
    end

    it "produces different refs for different identifiers" do
      described_class.installation_id = "install-a"
      first = described_class.installation_ref

      described_class.reset
      described_class.installation_id = "install-b"

      expect(described_class.installation_ref).not_to eq(first)
    end

    it "returns nil when there is nothing to hash" do
      expect(described_class.installation_ref).to be_nil
      expect(described_class.session_ref).to be_nil
      expect(described_class.user_ref).to be_nil
    end

    it "uses the internal primary key for user_ref, never an email" do
      described_class.user_id = 42

      expect(described_class.user_ref).to eq("u_42")
    end
  end

  describe "#build_group" do
    it "is nil when no build was reported, rather than claiming 'unknown'" do
      expect(described_class.build_group).to be_nil
    end

    it "buckets a reported build" do
      described_class.app_build = "51"

      expect(described_class.build_group).to eq(Observability::BuildGroup::REPORTED)
    end
  end

  describe ".sentry_tags" do
    it "carries refs and dimensions but never a raw identifier" do
      described_class.installation_id = "install-abc-123"
      described_class.platform = "android"
      described_class.app_build = "51"

      tags = described_class.sentry_tags

      expect(tags[:platform]).to eq("android")
      expect(tags[:build_group]).to eq("reported")
      expect(tags[:installation_ref]).to start_with("ins_")
      expect(tags.values.map(&:to_s)).not_to include("install-abc-123")
    end
  end

  describe ".for_task" do
    it "sets a correlation id and always resets, even when the block raises" do
      expect {
        described_class.for_task("some_task") { raise ArgumentError }
      }.to raise_error(ArgumentError)

      expect(described_class.job_key).to be_nil
      expect(described_class.request_id).to be_nil
    end

    it "exposes the task key while running" do
      described_class.for_task("some_task") do
        expect(described_class.job_key).to eq("some_task")
        expect(described_class.source).to eq("rake")
        expect(described_class.request_id).to be_present
      end
    end
  end
end
