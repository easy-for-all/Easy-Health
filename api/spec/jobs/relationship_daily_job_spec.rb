require "rails_helper"

RSpec.describe RelationshipDailyJob, type: :job do
  it "creates trial day events idempotently" do
    user = create(:user)
    user.update_columns(trial_started_at: 3.days.ago, trial_ends_at: 4.days.from_now)

    2.times { described_class.perform_now }

    expect(UserEvent.where(user: user, event_name: "trial_day_3").count).to eq(1)
  end

  it "creates inactivity threshold events once per last workout date" do
    user = create(:user)
    user.workout_sessions.create!(completed_at: 8.days.ago, duration_minutes: 30, completion_status: "completed")

    described_class.perform_now
    described_class.perform_now

    expect(UserEvent.where(user: user, event_name: "user_inactive_7_days").count).to eq(1)
  end
end
