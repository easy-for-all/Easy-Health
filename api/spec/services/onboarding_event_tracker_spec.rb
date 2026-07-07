require "rails_helper"

RSpec.describe OnboardingEventTracker do
  let(:user) { create(:user) }

  it "persists a valid event" do
    event = described_class.track(user: user, event_name: "onboarding_started", step_name: "choose_flow")

    expect(event).to be_persisted
    expect(event.event_name).to eq("onboarding_started")
  end

  it "does not persist and does not raise for an unknown event_name" do
    expect {
      result = described_class.track(user: user, event_name: "totally_unknown")
      expect(result).to be_nil
    }.not_to change(OnboardingEvent, :count)
  end

  it "does not persist and does not raise for an unknown onboarding_flow" do
    expect {
      described_class.track(user: user, event_name: "onboarding_flow_selected", onboarding_flow: "bogus")
    }.not_to change(OnboardingEvent, :count)
  end

  it "sets the user's onboarding_flow on first selection" do
    described_class.track(user: user, event_name: "onboarding_flow_selected", onboarding_flow: "quick")

    expect(user.reload.onboarding_flow).to eq("quick")
  end

  it "does not overwrite an already-attributed onboarding_flow" do
    user.update_column(:onboarding_flow, "quick")

    described_class.track(user: user, event_name: "onboarding_flow_selected", onboarding_flow: "complete")

    expect(user.reload.onboarding_flow).to eq("quick")
  end

  it "accepts free-form metadata" do
    event = described_class.track(
      user: user,
      event_name: "plan_created",
      onboarding_flow: "quick",
      metadata: { generated_plan_id: 42, duration_seconds: 12 }
    )

    expect(event.metadata).to eq("generated_plan_id" => 42, "duration_seconds" => 12)
  end
end
