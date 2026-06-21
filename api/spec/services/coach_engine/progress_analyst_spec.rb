require "rails_helper"

RSpec.describe CoachEngine::ProgressAnalyst do
  it "uses confirmed body-composition trends without storing raw values in its output" do
    user = create(:user)
    health_profile = create(:health_profile, user: user, goal: "lose_weight")
    fitness_profile = FitnessProfile.create!(user: user)
    user.health_data_points.create!(field_name: "body_fat_pct", value: 30, source_type: "exam", status: "confirmed", collected_at: 30.days.ago)
    user.health_data_points.create!(field_name: "body_fat_pct", value: 28, source_type: "exam", status: "confirmed", collected_at: Time.current)

    result = described_class.new(user: user, fitness_profile: fitness_profile, health_profile: health_profile).call

    expect(result["progress_direction"]).to eq("improving")
    expect(result.to_json).not_to include("30.0")
    expect(result.dig("evidence", "metric_trends", "body_fat_pct")).to eq("down")
  end
end
