require "rails_helper"

RSpec.describe FirstWorkoutNotStarted24hJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:daytime) { Time.utc(2026, 7, 20, 13, 0) } # 10:00 São Paulo

  def create_anchor(user, hours_ago:)
    event = UserEvent.create!(user: user, event_name: "activation_workout_created",
                              metadata: { "workout_plan_id" => 1 }, occurred_at: hours_ago.hours.ago)
    event.update_column(:created_at, hours_ago.hours.ago)
    event
  end

  def count_24h(user)
    UserEvent.where(user: user, event_name: "first_workout_not_started_24h").count
  end

  around { |ex| travel_to(daytime) { ex.run } }

  it "emits first_workout_not_started_24h for a plan created ~30h ago and no session" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    create_anchor(user, hours_ago: 30)

    described_class.perform_now

    expect(count_24h(user)).to eq(1)
  end

  it "does not emit when the user started between 2h and 24h (session exists)" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    create_anchor(user, hours_ago: 30)
    user.workout_sessions.create!(status: "in_progress")

    described_class.perform_now

    expect(count_24h(user)).to eq(0)
  end

  it "does not emit before 24h have passed" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    create_anchor(user, hours_ago: 10)

    described_class.perform_now

    expect(count_24h(user)).to eq(0)
  end

  it "emits the 24h event independently of an already-sent 2h event" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    create_anchor(user, hours_ago: 30)
    UserEvent.create!(user: user, event_name: "first_workout_not_started_2h", occurred_at: 28.hours.ago)

    described_class.perform_now

    expect(count_24h(user)).to eq(1)
  end
end
