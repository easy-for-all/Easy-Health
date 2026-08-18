require "rails_helper"

RSpec.describe MakePendingDeliveryRetry do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:now) { Time.zone.local(2026, 8, 17, 12, 0, 0) }

  def make_event(status, attrs = {})
    UserEvent.create!(
      {
        user: user,
        event_name: "first_workout_completed",
        occurred_at: now,
        created_at: now,
        updated_at: now,
        make_delivery_status: status
      }.merge(attrs)
    )
  end

  def terminal_message(event, status)
    attrs = {
      user: event.user,
      user_event: event,
      event_name: event.event_name,
      status: status,
      metadata_json: { "make_execution_id" => "exec-#{status}" }
    }

    case status
    when "sent"
      attrs[:sent_at] = now - 1.minute
    when "skipped"
      attrs[:sent_at] = nil
      attrs[:skipped_at] = now - 1.minute
    when "failed"
      attrs[:sent_at] = nil
      attrs[:failed_at] = now - 1.minute
      attrs[:error_message] = "Make terminal failure"
    end

    create(:relationship_message, attrs)
  end

  it "selects pending, due retrying, and stale sending events for redrive" do
    recent_pending = make_event("pending")
    old_pending = make_event("pending")
    old_pending.update_columns( # rubocop:disable Rails/SkipsModelValidations
      created_at: now - 2.hours,
      updated_at: now - 2.hours
    )
    due_retrying = make_event("retrying", make_next_retry_at: now - 1.minute)
    future_retrying = make_event("retrying", make_next_retry_at: now + 1.hour)
    stale_sending = make_event("sending", make_last_attempt_at: now - 10.minutes)
    fresh_sending = make_event("sending", make_last_attempt_at: now - 1.minute)

    pending = UserEvent.pending_make_delivery.where("created_at > ?", now - 1.hour)
    ids = described_class
          .retriable_scope(pending_scope: pending, now: now, stale_sending_before: now - 5.minutes)
          .pluck(:id)

    expect(ids).to include(recent_pending.id, due_retrying.id, stale_sending.id)
    expect(ids).not_to include(old_pending.id, future_retrying.id, fresh_sending.id)
  end

  it "records stale sending attempts as abandoned before redriving them" do
    event = make_event(
      "sending",
      make_attempts_count: 1,
      make_first_attempt_at: now - 10.minutes,
      make_last_attempt_at: now - 10.minutes
    )
    client = instance_double(MakeWebhookClient)

    allow(MakeWebhookClient).to receive(:new).and_return(client)
    allow(client).to receive(:deliver) do |delivered_event|
      expect(delivered_event.reload.make_delivery_status).to eq("retrying")
      expect(delivered_event.make_last_error).to eq(described_class::ABANDONED_SENDING_ERROR)
      expect(delivered_event.make_next_retry_at).to be_present
      MakeWebhookClient::Result.new(status: "accepted_by_make")
    end

    stats = described_class.call(scope: UserEvent.where(id: event.id), batch: false)

    expect(stats).to include(considered: 1, delivered: 1, failed: 0, recovered_sending: 1)
    expect(client).to have_received(:deliver).with(event)
  end

  RelationshipMessage::TERMINAL_STATUSES.each do |status|
    it "reconciles stale sending with relationship_message #{status} instead of redriving" do
      event = make_event(
        "sending",
        make_attempts_count: 1,
        make_first_attempt_at: now - 10.minutes,
        make_last_attempt_at: now - 10.minutes
      )
      terminal_message(event, status)

      expect(MakeWebhookClient).not_to receive(:new)

      stats = described_class.call(scope: UserEvent.where(id: event.id), batch: false)

      expect(stats).to include(considered: 1, delivered: 0, failed: 0, reconciled_terminal: 1)
      expect(event.reload.make_delivery_status).to eq("accepted_by_make")
      expect(event.make_processing_status).to eq(status)
      expect(event.make_execution_id).to eq("exec-#{status}")
    end
  end

  it "does not let two sweepers acquire the same stale sending event" do
    event = make_event(
      "sending",
      make_attempts_count: 1,
      make_first_attempt_at: now - 10.minutes,
      make_last_attempt_at: now - 10.minutes
    )
    client = instance_double(MakeWebhookClient)
    pending = UserEvent.none

    allow(MakeWebhookClient).to receive(:new).and_return(client)
    allow(client).to receive(:deliver).and_return(MakeWebhookClient::Result.new(status: "retrying"))

    travel_to(now) do
      first_scope = described_class.retriable_scope(pending_scope: pending, now: now)
      described_class.call(scope: first_scope, batch: false)

      second_scope = described_class.retriable_scope(pending_scope: pending, now: now)
      described_class.call(scope: second_scope, batch: false)
    end

    expect(client).to have_received(:deliver).once
    expect(event.reload.make_next_retry_at).to be > now
  end
end
