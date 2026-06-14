require "rails_helper"

RSpec.describe Ai::OpenaiCoachService do
  let(:user) { create(:user) }

  before do
    create(:health_profile, user: user, fitness_level: "intermediate", goal: "gain_muscle",
           age: 25, weight_kg: 70, height_cm: 175)
    allow(user).to receive(:paid_plan?).and_return(false)
  end

  describe ".enabled?" do
    it "returns false when OPENAI_ENABLED is false" do
      with_env("OPENAI_ENABLED" => "false") do
        expect(described_class.enabled?).to be false
      end
    end

    it "returns false when OPENAI_API_KEY is blank" do
      with_env("OPENAI_API_KEY" => "", "OPENAI_ENABLED" => "true") do
        expect(described_class.enabled?).to be false
      end
    end

    it "returns true when configured" do
      with_env("OPENAI_API_KEY" => "sk-test", "OPENAI_ENABLED" => "true") do
        expect(described_class.enabled?).to be true
      end
    end
  end

  describe "#within_daily_limit?" do
    subject { described_class.new(user) }

    context "when free user has not used any calls today" do
      it "returns true" do
        expect(subject.within_daily_limit?).to be true
      end
    end

    context "when free user has hit the daily limit" do
      before do
        stub_const("ENV", ENV.to_h.merge("OPENAI_DAILY_CALL_LIMIT_FREE" => "3"))
        3.times do
          AiUsageLog.create!(
            user:      user,
            provider:  "openai",
            task_type: "exercise_intent",
            model:     "gpt-4.1-mini",
            status:    "success",
          )
        end
      end

      it "returns false" do
        expect(subject.within_daily_limit?).to be false
      end
    end
  end

  describe "#parse_intent" do
    subject { described_class.new(user) }

    context "when OpenAI is disabled" do
      it "returns nil without calling the API" do
        stub_const("ENV", ENV.to_h.merge("OPENAI_ENABLED" => "false"))
        expect(subject.parse_intent("alguma coisa")).to be_nil
      end
    end

    context "when limit is reached" do
      before do
        allow(subject).to receive(:within_daily_limit?).and_return(false)
      end

      it "returns nil" do
        stub_const("ENV", ENV.to_h.merge("OPENAI_API_KEY" => "sk-test", "OPENAI_ENABLED" => "true"))
        expect(subject.parse_intent("alguma coisa")).to be_nil
      end
    end
  end
end

def with_env(vars)
  original = ENV.to_h
  vars.each { |k, v| ENV[k] = v }
  yield
ensure
  ENV.replace(original)
end
