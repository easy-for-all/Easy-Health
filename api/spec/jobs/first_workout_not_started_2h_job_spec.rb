require "rails_helper"

RSpec.describe FirstWorkoutNotStarted2hJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  # 10:00 in São Paulo (inside the 08–21 quiet-hours window).
  let(:daytime) { Time.utc(2026, 7, 20, 13, 0) }

  def create_anchor(user, hours_ago:)
    event = UserEvent.create!(user: user, event_name: "activation_workout_created",
                              metadata: { "workout_plan_id" => 1 }, occurred_at: hours_ago.hours.ago)
    event.update_column(:created_at, hours_ago.hours.ago)
    event
  end

  def event_count(user)
    UserEvent.where(user: user, event_name: "first_workout_not_started_2h").count
  end

  around { |ex| ex.metadata[:no_travel] ? ex.run : travel_to(daytime) { ex.run } }

  it "emits first_workout_not_started_2h for a plan created ~3h ago and no session" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    create_anchor(user, hours_ago: 3)

    described_class.perform_now

    expect(event_count(user)).to eq(1)
    expect(UserEvent.where(user: user, event_name: "push_event_eligible").count).to eq(1)
  end

  it "is idempotent across repeated runs" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    create_anchor(user, hours_ago: 3)

    2.times { described_class.perform_now }

    expect(event_count(user)).to eq(1)
  end

  it "does not emit when the user already started a workout (started before 2h)" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    create_anchor(user, hours_ago: 3)
    user.workout_sessions.create!(status: "in_progress")

    described_class.perform_now

    expect(event_count(user)).to eq(0)
  end

  it "does not emit before 2h have passed" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    create_anchor(user, hours_ago: 1)

    described_class.perform_now

    expect(event_count(user)).to eq(0)
  end

  it "skips outside the quiet-hours window, then emits on the next daytime run", :no_travel do
    user = create(:user, time_zone: "America/Sao_Paulo")

    travel_to(Time.utc(2026, 7, 20, 6, 0)) do # 03:00 São Paulo
      create_anchor(user, hours_ago: 3)
      described_class.perform_now
      expect(event_count(user)).to eq(0)
    end

    travel_to(Time.utc(2026, 7, 20, 13, 0)) do # 10:00 São Paulo (same anchor, still in window)
      described_class.perform_now
      expect(event_count(user)).to eq(1)
    end
  end
end
