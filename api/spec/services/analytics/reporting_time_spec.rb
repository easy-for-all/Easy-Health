require "rails_helper"

RSpec.describe Analytics::ReportingTime do
  it "defaults to the Brazilian reporting zone" do
    expect(described_class.zone.tzinfo.name).to eq("America/Sao_Paulo")
  end

  it "builds a timezone-aware local date SQL fragment (not raw UTC DATE())" do
    sql = described_class.local_date_sql("workout_sessions.completed_at")
    expect(sql).to include("AT TIME ZONE 'UTC'")
    expect(sql).to include("America/Sao_Paulo")
    expect(sql).to include("::date")
  end

  it "treats a cohort as immature until it has had the full observation window" do
    fresh = 2.days.ago
    old   = 10.days.ago
    expect(described_class.cohort_mature?(fresh, 7)).to be(false)
    expect(described_class.cohort_mature?(old, 7)).to be(true)
  end
end
