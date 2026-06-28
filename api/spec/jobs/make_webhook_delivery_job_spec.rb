require "rails_helper"

RSpec.describe MakeWebhookDeliveryJob, type: :job do
  it "does not attempt delivery after the maximum attempts" do
    user = create(:user, marketing_consent: true)
    event = RelationshipEventTracker.track(
      user: user,
      event_name: "first_workout_completed",
      idempotency_key: "first_workout_completed:max_attempts"
    )
    event.update!(make_delivery_status: "failed", make_attempts_count: described_class::MAX_ATTEMPTS)

    expect(MakeWebhookClient).not_to receive(:new)

    described_class.perform_now(event.id)

    expect(event.reload.make_last_error).to eq("max_attempts_reached")
  end
end
