require "rails_helper"

RSpec.describe RelationshipBackfillJob, type: :job do
  it "reports dry-run counts without creating events or segments" do
    user = create(:user)
    user.workout_plans.create!(active: true)
    events_before = UserEvent.count
    segments_before = UserSegment.count

    result = described_class.perform_now(dry_run: true)

    expect(result[:users_processed]).to be >= 1
    expect(result[:events_created]).to be > 0
    expect(UserEvent.count).to eq(events_before)
    expect(UserSegment.count).to eq(segments_before)
  end

  it "applies backfill while suppressing retroactive Make delivery by default" do
    user = create(:user, marketing_consent: true)
    user.workout_plans.create!(active: true)

    with_env(
      "MAKE_WEBHOOK_ENABLED" => "true",
      "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
      "MAKE_WEBHOOK_SECRET" => "secret",
      "MAKE_WEBHOOK_ALLOWED_EVENTS" => "workout_created"
    ) do
      result = described_class.perform_now(dry_run: false)

      expect(result[:events_created]).to be > 0
      expect(user.user_segments.reload.active.pluck(:segment_name)).to include("workout_created_not_started")
      expect(UserEvent.where(source: "relationship_backfill", event_name: "workout_created").last.make_delivery_status).to eq("disabled")
    end
  end
end
