require "rails_helper"

RSpec.describe Analytics::MetricResult do
  it "computes a rounded percentage with numerator/denominator/sample" do
    r = described_class.ratio(numerator: 21, denominator: 360, definition: "x_v1")
    json = r.as_json
    expect(json[:value]).to eq(5.8)
    expect(json[:numerator]).to eq(21)
    expect(json[:denominator]).to eq(360)
    expect(json[:sample_size]).to eq(360)
    expect(json[:status]).to eq("complete")
    expect(json[:definition]).to eq("x_v1")
  end

  it "never returns a negative percentage" do
    r = described_class.ratio(numerator: -5, denominator: 100, definition: "x_v1")
    expect(r.value).to be >= 0.0
  end

  it "clamps impossible >100% and flags it as inconsistent" do
    r = described_class.ratio(numerator: 150, denominator: 100, definition: "x_v1")
    expect(r.value).to eq(100.0)
    expect(r.status).to eq("inconsistent")
  end

  it "reports no_coverage instead of a misleading 0% when denominator is zero" do
    r = described_class.ratio(numerator: 0, denominator: 0, definition: "x_v1")
    expect(r.value).to eq(0.0)
    expect(r.status).to eq("no_coverage")
  end

  it "flags an insufficient sample below the minimum" do
    r = described_class.ratio(numerator: 1, denominator: 2, definition: "x_v1")
    expect(r.status).to eq("insufficient_sample")
  end
end
