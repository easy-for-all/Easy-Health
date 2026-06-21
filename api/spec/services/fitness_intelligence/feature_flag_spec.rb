require "rails_helper"

RSpec.describe FitnessIntelligence do
  around do |example|
    original = ENV[described_class::FEATURE_FLAG]
    example.run
  ensure
    ENV[described_class::FEATURE_FLAG] = original
  end

  it "defaults to disabled until a future generator opts in" do
    ENV.delete(described_class::FEATURE_FLAG)

    expect(described_class.enabled?).to be(false)
  end

  it "casts the environment flag as a boolean" do
    ENV[described_class::FEATURE_FLAG] = "true"

    expect(described_class.enabled?).to be(true)
  end
end
