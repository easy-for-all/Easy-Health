require "rails_helper"

RSpec.describe BlockLoadContextService do
  describe ".adjust" do
    it "returns 100% of the base weight for a single block" do
      expect(described_class.adjust(20.0, "single")).to eq(20.0)
    end

    it "returns ~90% for superset and bi_set" do
      expect(described_class.adjust(20.0, "superset")).to eq(18.0)
      expect(described_class.adjust(20.0, "bi_set")).to eq(18.0)
    end

    it "returns ~85% for tri_set" do
      expect(described_class.adjust(20.0, "tri_set")).to eq(17.0)
    end

    it "returns ~77.5% for circuit" do
      expect(described_class.adjust(20.0, "circuit")).to eq(15.5)
    end

    it "defaults to 100% for an unknown block type" do
      expect(described_class.adjust(20.0, "finisher")).to eq(20.0)
    end

    it "never invents a weight when base_weight is blank" do
      expect(described_class.adjust(nil, "superset")).to be_nil
    end
  end

  describe ".reason_suffix" do
    it "is nil for single (no adjustment to explain)" do
      expect(described_class.reason_suffix("single")).to be_nil
    end

    it "explains the discount for a multi-exercise block" do
      expect(described_class.reason_suffix("superset")).to eq("Ajustado para bloco: superset (~90% da carga isolada)")
    end
  end
end
