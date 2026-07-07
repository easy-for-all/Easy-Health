require "rails_helper"

RSpec.describe OnboardingEvent do
  let(:user) { create(:user) }

  it "is valid with a whitelisted event_name and no flow" do
    event = described_class.new(user: user, event_name: "onboarding_started")
    expect(event).to be_valid
  end

  it "is invalid with an unknown event_name" do
    event = described_class.new(user: user, event_name: "not_a_real_event")
    expect(event).not_to be_valid
  end

  it "is invalid with an unknown onboarding_flow" do
    event = described_class.new(user: user, event_name: "onboarding_flow_selected", onboarding_flow: "made_up")
    expect(event).not_to be_valid
  end

  it "is valid with each documented flow" do
    described_class::FLOWS.each do |flow|
      event = described_class.new(user: user, event_name: "onboarding_flow_selected", onboarding_flow: flow)
      expect(event).to be_valid
    end
  end

  it "defaults occurred_at to now when not set" do
    event = described_class.create!(user: user, event_name: "onboarding_started")
    expect(event.occurred_at).to be_within(5.seconds).of(Time.current)
  end
end
