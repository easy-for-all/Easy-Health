require "rails_helper"

RSpec.describe ActivationReminder24hJob, type: :job do
  def create_activation_event(user, hours_ago:)
    event = UserEvent.create!(user: user, event_name: "activation_workout_created", metadata: { "workout_plan_id" => 1 }, occurred_at: hours_ago.hours.ago)
    event.update_column(:created_at, hours_ago.hours.ago)
    event
  end

  it "fires activation_reminder_24h_due for a user who created a plan ~30h ago and never started a workout" do
    user = create(:user)
    create_activation_event(user, hours_ago: 30)

    described_class.perform_now

    expect(UserEvent.where(user: user, event_name: "activation_reminder_24h_due").count).to eq(1)
  end

  it "is idempotent across repeated runs" do
    user = create(:user)
    create_activation_event(user, hours_ago: 30)

    2.times { described_class.perform_now }

    expect(UserEvent.where(user: user, event_name: "activation_reminder_24h_due").count).to eq(1)
  end

  it "does not fire when the user already started a workout" do
    user = create(:user)
    create_activation_event(user, hours_ago: 30)
    user.workout_sessions.create!(status: "in_progress")

    described_class.perform_now

    expect(UserEvent.where(user: user, event_name: "activation_reminder_24h_due").count).to eq(0)
  end

  it "does not fire when the plan was created less than 24 hours ago" do
    user = create(:user)
    create_activation_event(user, hours_ago: 3)

    described_class.perform_now

    expect(UserEvent.where(user: user, event_name: "activation_reminder_24h_due").count).to eq(0)
  end

  it "does not fire when the plan is outside the lookback window (> 48h)" do
    user = create(:user)
    create_activation_event(user, hours_ago: 60)

    described_class.perform_now

    expect(UserEvent.where(user: user, event_name: "activation_reminder_24h_due").count).to eq(0)
  end
end
