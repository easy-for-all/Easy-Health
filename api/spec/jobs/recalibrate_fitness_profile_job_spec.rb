require "rails_helper"

RSpec.describe RecalibrateFitnessProfileJob, type: :job do
  let(:user) { create(:user) }
  let!(:fitness_profile) { create(:fitness_profile, user: user) }

  describe "#perform" do
    it "calls FitnessIntelligence.recalculate_safely with the user and source" do
      expect(FitnessIntelligence).to receive(:recalculate_safely)
        .with(user: user, source: "workout_completed")

      allow(CoachEngine::ContinuousCoach).to receive_message_chain(:new, :call)

      described_class.perform_now(user.id, source: "workout_completed")
    end

    it "calls CoachEngine::ContinuousCoach after recalibration" do
      allow(FitnessIntelligence).to receive(:recalculate_safely)

      continuous_coach_instance = instance_double(CoachEngine::ContinuousCoach, call: [])
      expect(CoachEngine::ContinuousCoach).to receive(:new)
        .with(user: user)
        .and_return(continuous_coach_instance)
      expect(continuous_coach_instance).to receive(:call)

      described_class.perform_now(user.id, source: "workout_completed")
    end

    it "uses 'event_trigger' as default source" do
      expect(FitnessIntelligence).to receive(:recalculate_safely)
        .with(user: user, source: "event_trigger")

      allow(CoachEngine::ContinuousCoach).to receive_message_chain(:new, :call)

      described_class.perform_now(user.id)
    end

    it "returns early when user does not exist" do
      expect(FitnessIntelligence).not_to receive(:recalculate_safely)
      expect(CoachEngine::ContinuousCoach).not_to receive(:new)

      described_class.perform_now(0)
    end

    it "does not raise when FitnessIntelligence raises an error" do
      allow(FitnessIntelligence).to receive(:recalculate_safely).and_raise(StandardError, "boom")

      expect { described_class.perform_now(user.id) }.not_to raise_error
    end

    it "is enqueued on the default queue" do
      expect(described_class.queue_name).to eq("default")
    end
  end
end
