require "rails_helper"

# BuildGroup is a DESCRIPTIVE cohort, never an eligibility rule.
#
# It used to hardcode a floor (RECONCILIATION_MIN_BUILD = 45) and label anything
# below it "legacy", on the premise that those builds could not send
# X-Installation-Id. That premise is false: the Android shell loads a remote web
# bundle, so a build 34 shell running today's bundle sends exactly the same
# header as a build 47. Reconciliation must therefore never branch on the build,
# and the cohort must not imply capability.
RSpec.describe Observability::BuildGroup do
  describe ".for" do
    it "reports a numeric build without ranking it when no floor is configured" do
      allow(Observability::Config).to receive(:current_build_min).and_return(nil)

      expect(described_class.for("34")).to eq(described_class::REPORTED)
      expect(described_class.for("47")).to eq(described_class::REPORTED)
    end

    it "classifies as current only against an explicitly configured floor" do
      allow(Observability::Config).to receive(:current_build_min).and_return(45)

      expect(described_class.for("47")).to eq(described_class::CURRENT)
      expect(described_class.for("34")).to eq(described_class::REPORTED)
    end

    it "treats a blank or non-numeric build as unknown, never as a failure" do
      allow(Observability::Config).to receive(:current_build_min).and_return(45)

      expect(described_class.for(nil)).to eq(described_class::UNKNOWN)
      expect(described_class.for("")).to eq(described_class::UNKNOWN)
      expect(described_class.for("unknown")).to eq(described_class::UNKNOWN)
    end

    it "no longer exposes a legacy cohort" do
      expect(described_class::ALL).to contain_exactly(
        described_class::UNKNOWN, described_class::REPORTED, described_class::CURRENT
      )
      expect(described_class.constants).not_to include(:LEGACY)
    end
  end

  it "keeps no build-based eligibility constant on AppInstallation" do
    # The old floor drove current_build/legacy_build scopes that silently
    # excluded rows from the link-rate denominator.
    expect(AppInstallation.constants).not_to include(:RECONCILIATION_MIN_BUILD)
    expect(AppInstallation).not_to respond_to(:current_build)
    expect(AppInstallation).not_to respond_to(:legacy_build)
  end
end
