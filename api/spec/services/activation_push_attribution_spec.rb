require "rails_helper"

RSpec.describe ActivationPushAttribution do
  let(:user) { build_eligible_push_user }

  describe ".on_workout_started" do
    it "cancels pending deliveries and attributes an opened push within 2h" do
      pending = NotificationDelivery.create!(user: user, notification_type: "first_workout_recovery", status: "scheduled", scheduled_for: 1.hour.from_now)
      opened = NotificationDelivery.create!(user: user, notification_type: "first_workout_reminder", status: "opened", opened_at: 10.minutes.ago)
      session = user.workout_sessions.create!(status: "in_progress")

      described_class.on_workout_started(user, session)

      expect(pending.reload.status).to eq("skipped")
      expect(opened.reload.status).to eq("converted")
      expect(UserEvent.where(user: user, event_name: "workout_started_from_push").count).to eq(1)
    end

    it "does not attribute when the push was opened long ago" do
      NotificationDelivery.create!(user: user, notification_type: "first_workout_reminder", status: "opened", opened_at: 5.hours.ago)
      session = user.workout_sessions.create!(status: "in_progress")

      described_class.on_workout_started(user, session)
      expect(UserEvent.where(user: user, event_name: "workout_started_from_push")).to be_empty
    end
  end
end
