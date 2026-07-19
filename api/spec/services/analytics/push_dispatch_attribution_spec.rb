require "rails_helper"

# Family A attribution: workout started/completed within 24h AFTER a push_dispatch
# was opened. Never attributes on send alone.
RSpec.describe Analytics::PushAttributionService, "push_dispatch attribution" do
  let(:user) { create(:user) }

  def opened_dispatch(opened_at:)
    PushDispatch.create!(
      user: user, notification_type: "activation_reminder", campaign_key: "first_workout_not_started_2h",
      idempotency_key: "d:#{SecureRandom.hex(4)}", status: "opened", opened_at: opened_at,
      payload_json: { "data" => { "event_name" => "first_workout_not_started_2h" } }
    )
  end

  def started_session(created_at: Time.current)
    user.workout_sessions.create!(status: "in_progress", created_at: created_at)
  end

  def completed_session(completed_at: Time.current)
    user.workout_sessions.create!(status: "completed", completion_status: "completed",
                                  duration_minutes: 30, completed_at: completed_at)
  end

  it "attributes a start within 24h of an open (open before start)" do
    opened_dispatch(opened_at: 3.hours.ago)

    described_class.attribute_dispatch_start(user, started_session)

    expect(UserEvent.exists?(user: user, event_name: "workout_started_from_push")).to be(true)
  end

  it "does NOT attribute when the open is older than 24h" do
    opened_dispatch(opened_at: 30.hours.ago)

    expect(described_class.attribute_dispatch_start(user, started_session)).to be_nil
    expect(UserEvent.exists?(user: user, event_name: "workout_started_from_push")).to be(false)
  end

  it "does not double-credit the same dispatch on repeated starts" do
    opened_dispatch(opened_at: 2.hours.ago)
    described_class.attribute_dispatch_start(user, started_session)
    described_class.attribute_dispatch_start(user, started_session)

    expect(UserEvent.where(user: user, event_name: "workout_started_from_push").count).to eq(1)
  end

  it "attributes completion only after the start was attributed" do
    opened_dispatch(opened_at: 2.hours.ago)

    described_class.attribute_dispatch_start(user, started_session)
    described_class.attribute_dispatch_completion(user, completed_session)

    expect(UserEvent.exists?(user: user, event_name: "workout_completed_from_push")).to be(true)
  end
end
