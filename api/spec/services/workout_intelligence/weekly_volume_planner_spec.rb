require "rails_helper"

RSpec.describe WorkoutIntelligence::WeeklyVolumePlanner do
  describe "#call" do
    it "never lets legs target fewer weekly sets than chest in a >=4x/week strength or hypertrophy plan" do
      planner = described_class.new(
        goal: "strength", fitness_level: "intermediate", days_per_week: 5,
        session_duration_minutes: 45, groups_in_template: %w[chest back legs core]
      )
      targets = planner.call

      expect(targets["legs"]).to be >= targets["chest"]
    end

    it "applies a focus boost to preferred body focus groups" do
      base = described_class.new(
        goal: "hypertrophy", fitness_level: "intermediate", days_per_week: 3,
        session_duration_minutes: 45, groups_in_template: %w[legs]
      ).call

      boosted = described_class.new(
        goal: "hypertrophy", fitness_level: "intermediate", days_per_week: 3,
        session_duration_minutes: 45, preferred_body_focus: %w[legs], groups_in_template: %w[legs]
      ).call

      expect(boosted["legs"]).to be > base["legs"]
    end

    it "scales volume down for shorter sessions" do
      short = described_class.new(
        goal: "hypertrophy", fitness_level: "intermediate", days_per_week: 3,
        session_duration_minutes: 15, groups_in_template: %w[chest]
      ).call

      long = described_class.new(
        goal: "hypertrophy", fitness_level: "intermediate", days_per_week: 3,
        session_duration_minutes: 60, groups_in_template: %w[chest]
      ).call

      expect(short["chest"]).to be < long["chest"]
    end

    it "gives core a minimum floor even under a low-volume goal" do
      targets = described_class.new(
        goal: "mobility", fitness_level: "beginner", days_per_week: 1,
        session_duration_minutes: 15, groups_in_template: %w[core]
      ).call

      expect(targets["core"]).to be >= described_class::CORE_MINIMUM_WEEKLY_SETS
    end
  end

  describe "#exercise_count" do
    it "distributes the weekly target across the group's occurrences in the week" do
      planner = described_class.new(
        goal: "strength", fitness_level: "intermediate", days_per_week: 5,
        session_duration_minutes: 45, groups_in_template: %w[legs]
      )
      planner.call

      once_a_week = planner.exercise_count(group: "legs", occurrences_in_week: 1)
      twice_a_week = planner.exercise_count(group: "legs", occurrences_in_week: 2)

      expect(once_a_week).to be >= twice_a_week
    end
  end
end
