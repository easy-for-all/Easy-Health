require "rails_helper"

RSpec.describe "Api::V1::NotificationPreferences", type: :request do
  let(:user) { create(:user) }
  before { sign_in user }

  it "defaults to opt-out (all flags false)" do
    get "/api/v1/notification_preferences"
    body = JSON.parse(response.body)
    expect(body["workout_reminders_enabled"]).to be(false)
    expect(body["push_enabled"]).to be(false)
  end

  it "opts in and stamps the permission funnel when push is enabled" do
    patch "/api/v1/notification_preferences", params: { push_enabled: true, workout_reminders_enabled: true }
    expect(response).to have_http_status(:ok)
    prefs = user.notification_preferences.reload
    expect(prefs.workout_reminders_enabled).to be(true)
    expect(prefs.permission_granted_at).to be_present
  end

  it "persists the preferred time on the health profile as manually_changed" do
    create(:health_profile, user: user)
    patch "/api/v1/notification_preferences", params: { preferred_workout_period: "morning", preferred_workout_time: "07:30" }
    profile = user.health_profile.reload
    expect(profile.preferred_workout_period).to eq("morning")
    expect(profile.preferred_workout_time.strftime("%H:%M")).to eq("07:30")
    expect(profile.workout_time_source).to eq("manually_changed")
  end

  it "cancels pending deliveries when reminders are turned off" do
    user.notification_preferences!.update!(workout_reminders_enabled: true, push_enabled: true)
    delivery = NotificationDelivery.create!(user: user, notification_type: "first_workout_reminder", status: "scheduled", scheduled_for: 1.hour.from_now)

    patch "/api/v1/notification_preferences", params: { workout_reminders_enabled: false }
    expect(delivery.reload.status).to eq("skipped")
  end

  it "disables all devices when push is turned off" do
    user.device_tokens.create!(token: "t1", platform: "android")
    user.notification_preferences!.update!(push_enabled: true)

    patch "/api/v1/notification_preferences", params: { push_enabled: false }
    expect(user.device_tokens.active).to be_empty
    expect(user.notification_preferences.reload.notifications_disabled_at).to be_present
  end

  it "creates preferences with push_enabled true on explicit consent when none exist" do
    expect(user.notification_preferences).to be_nil

    patch "/api/v1/notification_preferences", params: { push_enabled: true }

    expect(response).to have_http_status(:ok)
    prefs = user.notification_preferences.reload
    expect(prefs.push_enabled).to be(true)
    expect(prefs.notifications_disabled_at).to be_nil
    expect(prefs.disabled_reason).to be_nil
  end

  it "enables workout reminders only when explicitly accepted" do
    patch "/api/v1/notification_preferences", params: { push_enabled: true, workout_reminders_enabled: true }
    expect(user.notification_preferences.reload.workout_reminders_enabled).to be(true)
  end

  it "does not enable workout reminders implicitly when only push is accepted" do
    patch "/api/v1/notification_preferences", params: { push_enabled: true }
    expect(user.notification_preferences.reload.workout_reminders_enabled).to be(false)
  end

  it "keeps push_enabled false and does not set opt-out when consent is declined" do
    patch "/api/v1/notification_preferences", params: { push_enabled: false }

    prefs = user.notification_preferences.reload
    expect(prefs.push_enabled).to be(false)
    expect(prefs.notifications_disabled_at).to be_nil
  end

  it "sets a coherent disabled_reason when globally disabling push" do
    user.notification_preferences!.update!(push_enabled: true)

    patch "/api/v1/notification_preferences", params: { push_enabled: false }

    prefs = user.notification_preferences.reload
    expect(prefs.push_enabled).to be(false)
    expect(prefs.notifications_disabled_at).to be_present
    expect(prefs.disabled_reason).to eq("user_settings")
    expect(UserNotificationPreferences::DISABLED_REASONS).to include(prefs.disabled_reason)
  end

  it "does not globally opt out when only reminders are disabled" do
    user.notification_preferences!.update!(push_enabled: true, workout_reminders_enabled: true)

    patch "/api/v1/notification_preferences", params: { workout_reminders_enabled: false }

    prefs = user.notification_preferences.reload
    expect(prefs.push_enabled).to be(true)
    expect(prefs.workout_reminders_enabled).to be(false)
    expect(prefs.notifications_disabled_at).to be_nil
  end

  it "clears prior opt-out state when push is re-enabled" do
    user.notification_preferences!.update!(
      push_enabled: false,
      notifications_disabled_at: Time.current,
      disabled_reason: "user_settings"
    )

    patch "/api/v1/notification_preferences", params: { push_enabled: true }

    prefs = user.notification_preferences.reload
    expect(prefs.push_enabled).to be(true)
    expect(prefs.notifications_disabled_at).to be_nil
    expect(prefs.disabled_reason).to be_nil
  end
end
