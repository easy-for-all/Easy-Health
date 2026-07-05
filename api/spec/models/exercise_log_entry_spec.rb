require "rails_helper"

RSpec.describe ExerciseLogEntry do
  describe "#last_used_weight" do
    it "returns the last working (non-warmup) weight when one exists" do
      entry = described_class.new({
        "weight_by_set" => [10, 15, 15],
        "reps" => [12, 10, 8],
        "is_warmup_by_set" => [true, false, false]
      })

      expect(entry.last_used_weight).to eq(15.0)
    end

    it "falls back to the last weight of any kind when every set is warmup" do
      entry = described_class.new({
        "weight_by_set" => [5, 8],
        "reps" => [12, 10],
        "is_warmup_by_set" => [true, true]
      })

      expect(entry.last_used_weight).to eq(8.0)
    end

    it "falls back to weight_kg when weight_by_set is empty" do
      entry = described_class.new({ "weight_kg" => 20 })

      expect(entry.last_used_weight).to eq(20.0)
    end

    it "returns nil when there is no usable weight anywhere" do
      entry = described_class.new({ "weight_by_set" => [nil, 0] })

      expect(entry.last_used_weight).to be_nil
    end
  end

  describe "#total_volume_kg" do
    it "excludes warmup sets from volume" do
      entry = described_class.new({
        "weight_by_set" => [10, 15, 15],
        "reps" => [12, 10, 8],
        "is_warmup_by_set" => [true, false, false]
      })

      expect(entry.total_volume_kg).to eq((15 * 10) + (15 * 8))
    end
  end

  describe "#completed_sets_count" do
    it "counts sets with positive reps" do
      entry = described_class.new({ "reps" => [10, 0, 8, nil] })

      expect(entry.completed_sets_count).to eq(2)
    end
  end
end
