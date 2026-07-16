require "rails_helper"

RSpec.describe Analytics::PlatformComparison do
  def user_with(platform:, created_at: 10.days.ago)
    u = create(:user, activation_platform: platform)
    u.update_column(:created_at, created_at)
    u
  end

  def complete_workout!(user, completed_at:)
    user.workout_plans.create!
    user.workout_sessions.create!(
      status: "completed", completion_status: "completed",
      completed_at: completed_at, duration_minutes: 30
    )
  end

  it "cohorts users by activation_platform and returns MetricResults" do
    android = user_with(platform: "android")
    complete_workout!(android, completed_at: android.created_at + 2.hours) # activated within 24h

    web = user_with(platform: "web")
    web.workout_plans.create! # created but never completed

    result = described_class.new.call

    a = result[:cohorts]["android"]
    expect(a[:cohort_size]).to eq(1)
    expect(a[:created_workout].as_json[:numerator]).to eq(1)
    expect(a[:completed_workout].as_json[:numerator]).to eq(1)
    expect(a[:activation_24h].as_json[:numerator]).to eq(1)

    w = result[:cohorts]["web"]
    expect(w[:created_workout].as_json[:numerator]).to eq(1)
    expect(w[:completed_workout].as_json[:numerator]).to eq(0)
  end

  it "excludes test/anonymized users from cohorts" do
    tester = create(:user, activation_platform: "android", test_account: true)
    complete_workout!(tester, completed_at: Time.current)

    result = described_class.new.call
    expect(result[:cohorts]["android"][:cohort_size]).to eq(0)
  end

  it "carries the selection-bias note and event_tracked coverage" do
    result = described_class.new.call
    expect(result[:note]).to include("viés de seleção")
    expect(result[:coverage]).to eq("event_tracked")
  end
end
