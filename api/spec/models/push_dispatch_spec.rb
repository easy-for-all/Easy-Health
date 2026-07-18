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
    expect(build_dispatch(status: "failed").delivered?).to be(false)
    expect(build_dispatch(status: "skipped").delivered?).to be(false)
  end

  it "never exposes payload_json through as_json" do
    dispatch = build_dispatch(payload_json: { "route" => "/workouts/1" })
    expect(dispatch.as_json).not_to have_key("payload_json")
  end
end
