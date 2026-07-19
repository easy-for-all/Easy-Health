require "rails_helper"

RSpec.describe RelationshipDailyJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  # Run inside the quiet-hours window so inactivity emission is deterministic.
  around { |ex| travel_to(Time.utc(2026, 7, 20, 13, 0)) { ex.run } } # 10:00 São Paulo

  def complete_workout(user, at:)
    user.workout_sessions.create!(completed_at: at, duration_minutes: 30, completion_status: "completed")
  end

  it "creates trial day events idempotently" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    user.update_columns(trial_started_at: 3.days.ago, trial_ends_at: 4.days.from_now)

    2.times { described_class.perform_now }

    expect(UserEvent.where(user: user, event_name: "trial_day_3").count).to eq(1)
  end

  it "does not emit inactivity for a user who never completed a workout" do
    create(:user, time_zone: "America/Sao_Paulo")

    described_class.perform_now

    expect(UserEvent.where(event_name: %w[user_inactive_3_days user_inactive_7_days]).count).to eq(0)
  end

  it "emits user_inactive_3_days after 3 days without a completion" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    complete_workout(user, at: 3.days.ago)

    described_class.perform_now

    expect(UserEvent.where(user: user, event_name: "user_inactive_3_days").count).to eq(1)
  end

  it "emits inactivity events once per last workout date" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    complete_workout(user, at: 8.days.ago)

    2.times { described_class.perform_now }

    expect(UserEvent.where(user: user, event_name: "user_inactive_7_days").count).to eq(1)
  end

  it "ends the cycle when the user completes a new workout (no re-emission)" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    complete_workout(user, at: 8.days.ago)
    described_class.perform_now
    inactivity = -> { UserEvent.where(user: user, event_name: %w[user_inactive_3_days user_inactive_7_days]).count }
    before = inactivity.call

    # New completion moves last_workout_at to today → no longer inactive; a new
    # run emits nothing further for this cycle.
    complete_workout(user, at: Time.current)
    described_class.perform_now

    expect(inactivity.call).to eq(before)
  end

  it "no longer emits the removed user_inactive_15_days event" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    complete_workout(user, at: 20.days.ago)

    described_class.perform_now

    expect(UserEvent.where(user: user, event_name: "user_inactive_15_days").count).to eq(0)
  end
end
