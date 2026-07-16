require "rails_helper"

RSpec.describe Analytics::PushAttributionService do
  let(:user) { build_eligible_push_user }

  def opened_delivery(opened_at:)
    NotificationDelivery.create!(
      user: user,
      notification_type: "first_workout_reminder",
      status: "opened",
      opened_at: opened_at
    )
  end

  describe ".attribute_start" do
    # WorkoutSession.created_at is the workout start time (see the service).
    def session_started_at(time)
      s = user.workout_sessions.create!(status: "in_progress")
      s.update_column(:created_at, time)
      s
    end

    it "attributes a push opened within 2h and started after the open" do
      delivery = opened_delivery(opened_at: 10.minutes.ago)
      session = session_started_at(Time.current)

      described_class.attribute_start(user, session)

      expect(delivery.reload.status).to eq("converted")
      expect(ProductAnalyticsEvent.where(event_name: "workout_started_after_push").count).to eq(1)
      expect(UserEvent.where(user: user, event_name: "workout_started_from_push").count).to eq(1)
    end

    it "does NOT attribute a workout that started BEFORE the push was opened" do
      opened_delivery(opened_at: 10.minutes.ago)
      session = session_started_at(30.minutes.ago)

      described_class.attribute_start(user, session)

      expect(ProductAnalyticsEvent.where(event_name: "workout_started_after_push")).to be_empty
      expect(UserEvent.where(user: user, event_name: "workout_started_from_push")).to be_empty
    end

    it "does not attribute a push opened more than 2h ago" do
      opened_delivery(opened_at: 5.hours.ago)
      session = session_started_at(Time.current)

      described_class.attribute_start(user, session)
      expect(ProductAnalyticsEvent.where(event_name: "workout_started_after_push")).to be_empty
    end

    it "credits a push opened twice only once (no double attribution)" do
      opened_delivery(opened_at: 10.minutes.ago)
      session = session_started_at(Time.current)

      described_class.attribute_start(user, session)
      described_class.attribute_start(user, session) # e.g. the push was opened/handled twice

      expect(ProductAnalyticsEvent.where(event_name: "workout_started_after_push").count).to eq(1)
      expect(UserEvent.where(user: user, event_name: "workout_started_from_push").count).to eq(1)
    end
  end

  describe ".attribute_completion" do
    it "attributes completion within 24h of an attributed start, once" do
      delivery = opened_delivery(opened_at: 30.minutes.ago)
      delivery.update!(status: "converted", converted_at: 20.minutes.ago)
      session = user.workout_sessions.create!(status: "completed", completion_status: "completed", completed_at: Time.current, duration_minutes: 30)

      described_class.attribute_completion(user, session)
      described_class.attribute_completion(user, session)

      expect(ProductAnalyticsEvent.where(event_name: "workout_completed_after_push").count).to eq(1)
    end

    it "does not attribute completion without an attributed start" do
      session = user.workout_sessions.create!(status: "completed", completion_status: "completed", completed_at: Time.current, duration_minutes: 30)
      described_class.attribute_completion(user, session)
      expect(ProductAnalyticsEvent.where(event_name: "workout_completed_after_push")).to be_empty
    end
  end
end
