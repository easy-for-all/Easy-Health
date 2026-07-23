require "rails_helper"

RSpec.describe PushActivationEligibility do
  around { |ex| with_env("ACTIVATION_PUSH_ENABLED" => "true") { ex.run } }

  def reason(user, type: "first_workout_reminder")
    described_class.reason_ineligible(user, notification_type: type)
  end

  it "is eligible for a fully set-up opted-in user with a plan and no sessions" do
    user = build_eligible_push_user
    expect(reason(user)).to be_nil
    expect(described_class.eligible?(user, notification_type: "first_workout_reminder")).to be(true)
  end

  it "is not eligible when the flag is disabled" do
    user = build_eligible_push_user
    with_env("ACTIVATION_PUSH_ENABLED" => "false") do
      expect(reason(user)).to eq("flag_disabled")
    end
  end

  it "is not eligible when the user has no preferences row" do
    user = create(:user)
    expect(user.notification_preferences).to be_nil
    expect(reason(user)).to eq("no_preferences")
  end

  it "is not eligible without opt-in" do
    user = build_eligible_push_user
    user.notification_preferences.update!(workout_reminders_enabled: false)
    expect(reason(user)).to eq("reminders_disabled")
  end

  it "is not eligible without an active device" do
    user = build_eligible_push_user
    user.device_tokens.each { |d| d.invalidate!("test") }
    expect(reason(user)).to eq("no_active_device")
  end

  it "is not eligible without a plan" do
    user = build_eligible_push_user
    user.workout_plans.destroy_all
    expect(reason(user)).to eq("no_plan")
  end

  it "is not eligible once the user started/has any workout session" do
    user = build_eligible_push_user
    user.workout_sessions.create!(status: "in_progress")
    expect(reason(user)).to eq("already_engaged")
  end

  it "is not eligible without a preferred time" do
    user = build_eligible_push_user
    user.health_profile.update_columns(preferred_workout_time: nil, preferred_workout_period: "variable")
    expect(reason(user)).to eq("no_preferred_time")
  end

  it "blocks a second reminder once one was sent" do
    user = build_eligible_push_user
    user.notification_preferences.update!(activation_reminder_sent_at: 30.hours.ago)
    expect(reason(user, type: "first_workout_reminder")).to eq("already_sent")
  end

  it "requires the reminder before a recovery and enforces the min gap" do
    user = build_eligible_push_user
    expect(reason(user, type: "first_workout_recovery")).to eq("reminder_not_sent")

    user.notification_preferences.update!(activation_reminder_sent_at: 2.hours.ago)
    expect(reason(user, type: "first_workout_recovery")).to eq("too_soon")

    user.notification_preferences.update!(activation_reminder_sent_at: 30.hours.ago)
    expect(reason(user, type: "first_workout_recovery")).to be_nil
  end

  it "stops after the activation flow is completed (max 2)" do
    user = build_eligible_push_user
    user.notification_preferences.update!(activation_notifications_completed_at: Time.current)
    expect(reason(user)).to eq("flow_completed")
  end

  describe ".should_send?" do
    it "excludes the control group from sending but keeps them eligible" do
      user = build_eligible_push_user
      user.notification_preferences.update!(activation_push_variant: "control")
      expect(described_class.eligible?(user, notification_type: "first_workout_reminder")).to be(true)
      expect(described_class.should_send?(user, notification_type: "first_workout_reminder")).to be(false)
    end
  end
end
