require "rails_helper"

RSpec.describe FirstWorkoutNotStarted2hJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  # 10:00 in São Paulo (outside the 22:00–07:00 quiet-hours window).
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

  # The fact is independent of the clock. Quiet hours belong to dispatch, and
  # holding the event back until daytime used to lose it whenever the anchor
  # aged past the detection window overnight.
  it "emits inside the quiet-hours window too", :no_travel do
    user = create(:user, time_zone: "America/Sao_Paulo")

    travel_to(Time.utc(2026, 7, 20, 6, 0)) do # 03:00 São Paulo
      create_anchor(user, hours_ago: 3)
      described_class.perform_now

      expect(event_count(user)).to eq(1)
    end
  end

  it "does not duplicate when a later run happens outside quiet hours", :no_travel do
    user = create(:user, time_zone: "America/Sao_Paulo")

    travel_to(Time.utc(2026, 7, 20, 6, 0)) do # 03:00 São Paulo
      create_anchor(user, hours_ago: 3)
      described_class.perform_now
    end

    travel_to(Time.utc(2026, 7, 20, 13, 0)) do # 10:00 São Paulo
      described_class.perform_now
    end

    expect(event_count(user)).to eq(1)
  end

  it "carries the anchor reference and its origin into the metadata" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    anchor = create_anchor(user, hours_ago: 3)
    anchor.update_column(:origin_surface, "android")

    described_class.perform_now

    metadata = UserEvent.find_by(user: user, event_name: "first_workout_not_started_2h").metadata
    expect(metadata["anchor_event_id"]).to eq(anchor.id)
    expect(metadata["anchor_origin_surface"]).to eq("android")
  end

  it "reports counters on the heartbeat metadata" do
    user = create(:user, time_zone: "America/Sao_Paulo")
    create_anchor(user, hours_ago: 3)

    job = described_class.new
    stats = job.perform

    expect(stats[:candidates_found]).to eq(1)
    expect(stats[:events_created]).to eq(1)
    expect(job.heartbeat_metadata).to eq(stats)
  end
end
