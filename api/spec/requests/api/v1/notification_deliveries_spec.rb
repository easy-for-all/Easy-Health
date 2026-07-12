require "rails_helper"

RSpec.describe "Api::V1::NotificationDeliveries", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  def delivery(type: "first_workout_reminder", status: "sent")
    NotificationDelivery.create!(user: user, notification_type: type, status: status)
  end

  describe "POST opened" do
    it "records the open" do
      d = delivery
      post "/api/v1/notification_deliveries/#{d.id}/opened"
      expect(response).to have_http_status(:ok)
      expect(d.reload.opened_at).to be_present
    end

    it "cannot open another user's delivery" do
      other = NotificationDelivery.create!(user: create(:user), notification_type: "first_workout_reminder", status: "sent")
      post "/api/v1/notification_deliveries/#{other.id}/opened"
      expect(response).to have_http_status(:not_found)
      expect(other.reload.opened_at).to be_nil
    end
  end

  describe "POST dislike" do
    it "disables reminders on 'not_this_type'" do
      user.notification_preferences!.update!(workout_reminders_enabled: true)
      post "/api/v1/notification_deliveries/#{delivery.id}/dislike", params: { reason: "not_this_type" }
      expect(response).to have_http_status(:ok)
      expect(user.notification_preferences.reload.workout_reminders_enabled).to be(false)
    end

    it "cancels pending recovery on 'too_many' and ends the flow" do
      pending_recovery = NotificationDelivery.create!(user: user, notification_type: "first_workout_recovery", status: "scheduled", scheduled_for: 1.hour.from_now)
      post "/api/v1/notification_deliveries/#{delivery.id}/dislike", params: { reason: "too_many" }
      expect(pending_recovery.reload.status).to eq("skipped")
      expect(user.notification_preferences.reload.activation_notifications_completed_at).to be_present
    end

    it "rejects an unknown reason" do
      post "/api/v1/notification_deliveries/#{delivery.id}/dislike", params: { reason: "whatever" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
