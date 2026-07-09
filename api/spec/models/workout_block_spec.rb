require "rails_helper"

RSpec.describe WorkoutBlock, type: :model do
  let(:user) { create(:user) }
  let(:plan) { user.workout_plans.create!(active: true) }
  let(:day) { plan.workout_days.create!(name: "Treino A", day_of_week: 1) }

  describe "validations" do
    it "is valid with a known block_type" do
      block = day.workout_blocks.build(block_type: "superset", position: 0, rounds: 3)
      expect(block).to be_valid
    end

    it "rejects an unknown block_type" do
      block = day.workout_blocks.build(block_type: "bogus", position: 0, rounds: 1)
      expect(block).not_to be_valid
      expect(block.errors[:block_type]).to be_present
    end

    it "requires rounds to be a positive integer" do
      block = day.workout_blocks.build(block_type: "single", position: 0, rounds: 0)
      expect(block).not_to be_valid
    end
  end

  describe "block_type is queryable for admin/log purposes" do
    it "supports grouping and counting by block_type" do
      day.workout_blocks.create!(block_type: "single", position: 0, rounds: 1)
      day.workout_blocks.create!(block_type: "superset", position: 1, rounds: 3)
      day.workout_blocks.create!(block_type: "superset", position: 2, rounds: 3)

      expect(WorkoutBlock.group(:block_type).count).to eq("single" => 1, "superset" => 2)
    end
  end

  describe "#multi_exercise?" do
    it "is true for superset, bi_set, tri_set and circuit" do
      %w[superset bi_set tri_set circuit].each do |type|
        block = day.workout_blocks.create!(block_type: type, position: 0, rounds: 3)
        expect(block).to be_multi_exercise
      end
    end

    it "is false for single and other block types" do
      %w[single warmup cooldown finisher].each do |type|
        block = day.workout_blocks.create!(block_type: type, position: 0, rounds: 1)
        expect(block).not_to be_multi_exercise
      end
    end
  end
end
