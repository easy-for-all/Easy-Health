require "rails_helper"

RSpec.describe CoachInsight, type: :model do
  let(:user) { create(:user) }
  let(:fitness_profile) { create(:fitness_profile, user: user) }

  def build_insight(overrides = {})
    CoachInsight.new(
      {
        user:            user,
        fitness_profile: fitness_profile,
        insight_type:    "inactivity",
        title:           "Hora de retomar!",
        message:         "Você ficou 10 dias sem treinar.",
        severity:        "warning",
        source:          "continuous_coach"
      }.merge(overrides)
    )
  end

  describe "validations" do
    it "is valid with all required attributes" do
      expect(build_insight).to be_valid
    end

    it "requires user" do
      insight = build_insight(user: nil)
      expect(insight).not_to be_valid
    end

    it "requires fitness_profile" do
      insight = build_insight(fitness_profile: nil)
      expect(insight).not_to be_valid
    end

    it "requires insight_type" do
      insight = build_insight(insight_type: nil)
      expect(insight).not_to be_valid
    end

    it "requires title" do
      insight = build_insight(title: nil)
      expect(insight).not_to be_valid
    end

    it "requires message" do
      insight = build_insight(message: nil)
      expect(insight).not_to be_valid
    end

    it "requires source" do
      insight = build_insight(source: nil)
      expect(insight).not_to be_valid
    end
  end

  describe "associations" do
    it "belongs to user" do
      expect(build_insight.user).to eq(user)
    end

    it "belongs to fitness_profile" do
      expect(build_insight.fitness_profile).to eq(fitness_profile)
    end
  end

  describe "scopes" do
    let!(:unread) { create(:coach_insight, user: user, fitness_profile: fitness_profile, read_at: nil) rescue nil }
    let!(:read)   { create(:coach_insight, user: user, fitness_profile: fitness_profile, read_at: Time.current) rescue nil }

    it "returns unread insights" do
      # Using direct ActiveRecord scope when factory not available
      unread_insight = CoachInsight.create!(
        user: user, fitness_profile: fitness_profile,
        insight_type: "inactivity", title: "T", message: "M",
        severity: "info", source: "continuous_coach", read_at: nil
      )
      read_insight = CoachInsight.create!(
        user: user, fitness_profile: fitness_profile,
        insight_type: "risk", title: "T2", message: "M2",
        severity: "warning", source: "risk_analyst", read_at: 1.hour.ago
      )

      expect(CoachInsight.unread).to include(unread_insight)
      expect(CoachInsight.unread).not_to include(read_insight)
    end
  end

  describe "#mark_read!" do
    it "sets read_at to current time" do
      insight = CoachInsight.create!(
        user: user, fitness_profile: fitness_profile,
        insight_type: "inactivity", title: "T", message: "M",
        severity: "info", source: "continuous_coach"
      )

      expect { insight.mark_read! }.to change { insight.reload.read_at }.from(nil)
    end

    it "does not update read_at if already read" do
      original_time = 1.hour.ago
      insight = CoachInsight.create!(
        user: user, fitness_profile: fitness_profile,
        insight_type: "inactivity", title: "T", message: "M",
        severity: "info", source: "continuous_coach",
        read_at: original_time
      )

      insight.mark_read!
      expect(insight.reload.read_at).to be_within(1.second).of(original_time)
    end
  end

  describe "constants" do
    it "defines valid insight types" do
      expect(CoachInsight::INSIGHT_TYPES).to include("adherence", "inactivity", "achievement", "risk")
    end

    it "defines valid severities" do
      expect(CoachInsight::SEVERITIES).to eq(%w[info warning success])
    end

    it "defines valid sources" do
      expect(CoachInsight::SOURCES).to include("continuous_coach", "risk_analyst")
    end
  end
end
