require "rails_helper"

RSpec.describe RelationshipDailyJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  around { |ex| ex.metadata[:no_travel] ? ex.run : travel_to(Time.utc(2026, 7, 20, 13, 0)) { ex.run } }

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

  # The production cron fires at 08:00 UTC, which is 05:00 in São Paulo. The old
  # quiet-hours gate made that return no candidates at all, so these events
  # simply never existed for Brazilian users.
  context "when the cron runs inside the user's quiet hours", :no_travel do
    it "still emits user_inactive_3_days" do
      user = create(:user, time_zone: "America/Sao_Paulo")

      travel_to(Time.utc(2026, 7, 20, 8, 0)) do # 05:00 São Paulo
        complete_workout(user, at: 3.days.ago)
        described_class.perform_now
      end

      expect(UserEvent.where(user: user, event_name: "user_inactive_3_days").count).to eq(1)
    end

    it "still emits user_inactive_7_days" do
      user = create(:user, time_zone: "America/Sao_Paulo")

      travel_to(Time.utc(2026, 7, 20, 8, 0)) do # 05:00 São Paulo
        complete_workout(user, at: 8.days.ago)
        described_class.perform_now
      end

      expect(UserEvent.where(user: user, event_name: "user_inactive_7_days").count).to eq(1)
    end
  end

  describe "catch-up" do
    it "emits both thresholds when both were crossed unnoticed" do
      user = create(:user, time_zone: "America/Sao_Paulo")
      complete_workout(user, at: 10.days.ago)

      described_class.perform_now

      names = UserEvent.where(user: user).pluck(:event_name)
      expect(names).to include("user_inactive_3_days", "user_inactive_7_days")
    end

    it "marks a late detection as catch-up and says when the threshold was crossed" do
      user = create(:user, time_zone: "America/Sao_Paulo")
      complete_workout(user, at: 10.days.ago)

      described_class.perform_now

      metadata = UserEvent.find_by(user: user, event_name: "user_inactive_3_days").metadata
      expect(metadata["catchup"]).to be(true)
      expect(metadata["threshold_days"]).to eq(3)
      expect(Time.zone.parse(metadata["threshold_crossed_at"])).to be_within(1.day).of(7.days.ago)
      expect(metadata["detected_at"]).to be_present
    end

    it "does not mark an on-time detection as catch-up" do
      user = create(:user, time_zone: "America/Sao_Paulo")
      complete_workout(user, at: 3.days.ago)

      described_class.perform_now

      metadata = UserEvent.find_by(user: user, event_name: "user_inactive_3_days").metadata
      expect(metadata["catchup"]).to be(false)
    end
  end

  it "stamps the scheduler as the origin surface" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    complete_workout(user, at: 3.days.ago)

    described_class.perform_now

    expect(UserEvent.find_by(user: user, event_name: "user_inactive_3_days").origin_surface)
      .to eq("backend_scheduler")
  end
end
