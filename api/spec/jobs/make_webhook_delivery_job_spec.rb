require "rails_helper"

RSpec.describe MakeWebhookDeliveryJob, type: :job do
  it "does not attempt delivery after the maximum attempts" do
    user = create(:user, marketing_consent: true)
    event = RelationshipEventTracker.track(
      user: user,
      event_name: "first_workout_completed",
      idempotency_key: "first_workout_completed:max_attempts"
    )
    event.update!(make_delivery_status: "retrying", make_attempts_count: described_class::MAX_ATTEMPTS)

    expect(MakeWebhookClient).not_to receive(:new)

    described_class.perform_now(event.id)

    expect(event.reload.make_delivery_status).to eq("dead_letter")
    expect(event.make_last_error).to eq("max_attempts_reached")
  end

  it "reconciles a terminal relationship message instead of attempting delivery" do
    user = create(:user, marketing_consent: true)
    event = UserEvent.create!(
      user: user,
      event_name: "first_workout_completed",
      occurred_at: Time.current,
      make_delivery_status: "sending",
      make_attempts_count: 1
    )
    create(:relationship_message, :skipped, user: user, user_event: event, event_name: event.event_name)

    expect(MakeWebhookClient).not_to receive(:new)

    described_class.perform_now(event.id)

    expect(event.reload.make_delivery_status).to eq("accepted_by_make")
    expect(event.make_processing_status).to eq("skipped")
  end
end
