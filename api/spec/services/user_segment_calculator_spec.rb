require "rails_helper"

RSpec.describe UserSegmentCalculator do
  it "activates trial, no workout and no body photo segments" do
    user = create(:user)

    result = described_class.call(user)

    expect(result.active_segments).to include("trial_active", "never_created_workout", "no_body_photo")
    expect(user.user_segments.active.pluck(:segment_name)).to include("trial_active", "never_created_workout", "no_body_photo")
  end

  it "activates workout_created_not_started when a plan exists without sessions" do
    user = create(:user)
    user.workout_plans.create!(active: true)

    result = described_class.call(user)

    expect(result.active_segments).to include("workout_created_not_started")
  end

  it "activates active_user and completed_partial_recently from recent sessions" do
    user = create(:user)
    user.workout_sessions.create!(completed_at: 2.days.ago, duration_minutes: 30, completion_status: "completed")
    user.workout_sessions.create!(completed_at: 1.day.ago, duration_minutes: 30, completion_status: "completed_partial")

    result = described_class.call(user)

    expect(result.active_segments).to include("active_user", "completed_partial_recently", "first_workout_done")
  end

  it "activates churn_risk for inactive active subscribers" do
    user = create(:user)
    user.create_subscription!(status: "active", plan_name: "pro_monthly")
    user.workout_sessions.create!(completed_at: 8.days.ago, duration_minutes: 30, completion_status: "completed")

    result = described_class.call(user)

    expect(result.active_segments).to include("subscriber_active", "inactive_7_days", "churn_risk")
  end
end
