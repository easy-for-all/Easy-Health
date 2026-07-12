require "rails_helper"

RSpec.describe FirstWorkoutReminderEligibilityJob do
  around { |ex| with_env("ACTIVATION_PUSH_ENABLED" => "true") { ex.run } }

  def make_candidate
    user = build_eligible_push_user
    UserEvent.create!(user: user, event_name: "activation_workout_created", occurred_at: Time.current)
    user
  end

  it "schedules exactly one delivery per candidate (idempotent across sweeps)" do
    user = make_candidate

    described_class.perform_now
    described_class.perform_now

    deliveries = NotificationDelivery.where(user: user, notification_type: "first_workout_reminder")
    expect(deliveries.count).to eq(1)
    expect(deliveries.first.status).to eq("scheduled")
  end

  it "schedules for a future local time (never immediately in the past)" do
    user = make_candidate
    described_class.perform_now
    delivery = NotificationDelivery.find_by(user: user)
    expect(delivery.scheduled_for).to be > Time.current
  end

  it "does not schedule ineligible users" do
    user = make_candidate
    user.notification_preferences.update!(workout_reminders_enabled: false)
    described_class.perform_now
    expect(NotificationDelivery.where(user: user)).to be_empty
  end
end
