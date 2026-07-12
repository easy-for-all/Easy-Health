require "rails_helper"

RSpec.describe PushDispatchService do
  around { |ex| with_env("ACTIVATION_PUSH_ENABLED" => "true") { ex.run } }

  let(:user) { build_eligible_push_user }

  def scheduled_delivery(type: "first_workout_reminder")
    NotificationDelivery.create!(
      user: user, notification_type: type, status: "scheduled",
      scheduled_for: 1.minute.ago, idempotency_key: "#{type}:#{user.id}:#{SecureRandom.hex(4)}"
    )
  end

  def stub_fcm(result)
    allow_any_instance_of(FirebasePushService).to receive(:deliver).and_return(result)
  end

  def sent_result
    FirebasePushService::Result.new(status: "sent", message_id: "mock/1", invalid_token: false)
  end

  it "sends a due delivery and stamps the reminder timestamp" do
    stub_fcm(sent_result)
    delivery = scheduled_delivery

    expect(described_class.new(delivery).call).to eq(:sent)
    expect(delivery.reload.status).to eq("sent")
    expect(user.notification_preferences.reload.activation_reminder_sent_at).to be_present
  end

  it "ends the flow after the recovery is sent (max 2)" do
    stub_fcm(sent_result)
    user.notification_preferences.update!(activation_reminder_sent_at: 30.hours.ago)
    delivery = scheduled_delivery(type: "first_workout_recovery")

    expect(described_class.new(delivery).call).to eq(:sent)
    expect(user.notification_preferences.reload.activation_notifications_completed_at).to be_present
  end

  it "invalidates a dead token and fails/retries" do
    stub_fcm(FirebasePushService::Result.new(status: "failed", error_code: "UNREGISTERED", invalid_token: true))
    delivery = scheduled_delivery

    described_class.new(delivery).call
    expect(user.device_tokens.first.reload.invalidated_at).to be_present
    expect(delivery.reload.retry_count).to be >= 1
  end

  it "skips the control group without sending" do
    user.notification_preferences.update!(activation_push_variant: "control")
    expect_any_instance_of(FirebasePushService).not_to receive(:deliver)
    delivery = scheduled_delivery

    expect(described_class.new(delivery).call).to eq(:skipped)
    expect(delivery.reload.status).to eq("skipped")
  end

  it "skips when the user became ineligible before sending" do
    user.workout_sessions.create!(status: "in_progress") # already engaged
    delivery = scheduled_delivery

    expect(described_class.new(delivery).call).to eq(:skipped)
    expect(delivery.reload.cancel_reason).to eq("already_engaged")
  end

  it "does not double-send: a claimed delivery is not re-sent" do
    stub_fcm(sent_result)
    delivery = scheduled_delivery
    described_class.new(delivery).call
    # Second dispatch of the same row (now 'sent') must not re-claim.
    expect(described_class.new(delivery).call).to eq(:skipped)
  end
end
