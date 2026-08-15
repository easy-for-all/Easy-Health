require "rails_helper"

RSpec.describe PushDispatch do
  let(:user) { create(:user) }

  def build_dispatch(**attrs)
    described_class.new(
      { user: user, notification_type: "workout_reminder", status: "received",
        idempotency_key: "evt:camp:#{user.id}:workout_reminder" }.merge(attrs)
    )
  end

  it "enforces idempotency_key uniqueness (Phase 9 exclusivity)" do
    build_dispatch.save!
    dup = build_dispatch
    expect(dup).not_to be_valid
    expect(dup.errors[:idempotency_key]).to be_present
  end

  it "raises at the DB level on a duplicate idempotency_key" do
    build_dispatch.save!
    expect do
      described_class.insert!({
        user_id: user.id, notification_type: "workout_reminder", status: "received",
        idempotency_key: "evt:camp:#{user.id}:workout_reminder"
      })
    end.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "considers only delivered statuses as delivered?" do
    expect(build_dispatch(status: "provider_accepted").delivered?).to be(true)
    expect(build_dispatch(status: "partially_accepted").delivered?).to be(true)
    expect(build_dispatch(status: "opened").delivered?).to be(true)
    expect(build_dispatch(status: "deferred").delivered?).to be(false)
    expect(build_dispatch(status: "failed").delivered?).to be(false)
    expect(build_dispatch(status: "skipped").delivered?).to be(false)
  end

  it "stores quiet-hours deferral without using skip_reason" do
    dispatch = build_dispatch
    dispatch.save!

    dispatch.mark_deferred!(reason: "quiet_hours", next_allowed_at: 1.hour.from_now)

    expect(dispatch.status).to eq("deferred")
    expect(dispatch.skip_reason).to be_nil
    expect(dispatch.defer_reason).to eq("quiet_hours")
    expect(dispatch.next_allowed_at).to be_present
  end

  it "declares and enforces the allowed lifecycle transitions" do
    dispatch = build_dispatch
    dispatch.save!

    dispatch.mark_deferred!(reason: "quiet_hours", next_allowed_at: 1.hour.from_now)
    dispatch.update!(status: "processing")
    dispatch.update!(status: "provider_accepted")
    dispatch.mark_opened!

    expect(dispatch.status).to eq("opened")
  end

  it "rejects invalid lifecycle jumps" do
    dispatch = build_dispatch
    dispatch.save!

    expect { dispatch.update!(status: "provider_accepted") }
      .to raise_error(ActiveRecord::RecordInvalid, /cannot transition from received to provider_accepted/)
  end

  it "never exposes payload_json through as_json" do
    dispatch = build_dispatch(payload_json: { "route" => "/workouts/1" })
    expect(dispatch.as_json).not_to have_key("payload_json")
  end
end
