require "rails_helper"

RSpec.describe ScheduledWorkoutReminderSchedulerJob, type: :job do
  scheduled_reminder_make_env = {
    "SCHEDULED_WORKOUT_REMINDER_ENABLED" => "true",
    "MAKE_WEBHOOK_ENABLED" => "true",
    "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
    "MAKE_WEBHOOK_SECRET" => "secret",
    "MAKE_WEBHOOK_ALLOWED_EVENTS" => "scheduled_workout_reminder_due",
    "MAKE_EVENT_SCHEMA_VERSION" => "2"
  }.freeze

  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
  let(:now) { zone.local(2026, 7, 21, 6, 30) }

  around { |ex| with_env(scheduled_reminder_make_env) { ex.run } }

  before do
    allow(MakeWebhookDeliveryJob).to receive(:perform_later)
  end

  def build_candidate(preferred_time: "07:00", period: "morning", plan_created_at: now - 1.day)
    user = create(:user, marketing_consent: true, time_zone: "America/Sao_Paulo")
    create(:health_profile, user: user, preferred_workout_period: period, preferred_workout_time: preferred_time)
    plan = user.workout_plans.create!(active: true)
    plan.update_columns(created_at: plan_created_at, updated_at: plan_created_at) # rubocop:disable Rails/SkipsModelValidations
    day = plan.workout_days.create!(name: "Treino A", day_of_week: 1, position: 1)
    create(:device_token, user: user, permission_status: "granted")
    user.notification_preferences!.update!(push_enabled: true, workout_reminders_enabled: true)
    [ user, plan, day ]
  end

  def reminder_events(user)
    user.user_events.where(event_name: "scheduled_workout_reminder_due")
  end

  def create_reminder_event(user, plan, local_date:, reminder_number: 1, status: "delivered")
    user.user_events.create!(
      event_name: "scheduled_workout_reminder_due",
      occurred_at: Time.zone.parse("#{local_date} 09:30:00"),
      make_delivery_status: status,
      metadata: {
        campaign: ScheduledWorkoutReminderEligibility::CAMPAIGN,
        activation: {
          plan_id: plan.id,
          reminder_local_date: local_date,
          reminder_number: reminder_number
        }
      },
      idempotency_key: "scheduled-workout-reminder:v1:user:#{user.id}:plan:#{plan.id}:date:#{local_date}"
    )
  end

  it "emits one event at 06:30 for a 07:00 preference and enqueues Make delivery" do
    user, plan, day = build_candidate

    stats = described_class.perform_now(now: now)

    event = reminder_events(user).last
    expect(stats[:event_created]).to eq(1)
    expect(event.metadata["campaign"]).to eq(ScheduledWorkoutReminderEligibility::CAMPAIGN)
    expect(event.metadata.dig("activation", "plan_id")).to eq(plan.id)
    expect(event.metadata.dig("activation", "workout_id")).to eq(day.id)
    expect(event.metadata.dig("activation", "reminder_time")).to eq("06:30")
    expect(event.metadata.dig("activation", "reminder_number")).to eq(1)
    expect(event.idempotency_key).to eq("scheduled-workout-reminder:v1:user:#{user.id}:plan:#{plan.id}:date:2026-07-21")
    expect(MakeWebhookDeliveryJob).to have_received(:perform_later).with(event.id)
  end

  it "does not emit before the valid window" do
    user, = build_candidate

    described_class.perform_now(now: zone.local(2026, 7, 21, 6, 29))

    expect(reminder_events(user)).to be_empty
  end

  it "emits at most one event per local reminder date" do
    user, = build_candidate

    described_class.perform_now(now: now)
    described_class.perform_now(now: now + 1.minute)

    expect(reminder_events(user).count).to eq(1)
  end

  it "creates reminder numbers 1, 2 and 3, then never creates reminder 4" do
    user, plan = build_candidate
    create_reminder_event(user, plan, local_date: "2026-07-19", reminder_number: 1)
    create_reminder_event(user, plan, local_date: "2026-07-20", reminder_number: 2)

    described_class.perform_now(now: now)

    third = reminder_events(user).order(:created_at).last
    expect(third.metadata.dig("activation", "reminder_number")).to eq(3)

    described_class.perform_now(now: zone.local(2026, 7, 22, 6, 30))

    expect(reminder_events(user).count).to eq(3)
  end

  it "does not create a replacement event when a previous Make delivery failed" do
    user, plan = build_candidate
    create_reminder_event(user, plan, local_date: "2026-07-19", reminder_number: 1, status: "failed")
    create_reminder_event(user, plan, local_date: "2026-07-20", reminder_number: 2, status: "failed")
    create_reminder_event(user, plan, local_date: "2026-07-21", reminder_number: 3, status: "failed")

    described_class.perform_now(now: now)

    expect(reminder_events(user).count).to eq(3)
  end

  it "stops after the user completed a workout following the first reminder" do
    user, _plan, day = build_candidate
    described_class.perform_now(now: now)
    user.workout_sessions.create!(
      workout_day: day,
      status: "completed",
      completion_status: "completed",
      completed_at: now + 2.hours,
      duration_minutes: 30
    )

    described_class.perform_now(now: zone.local(2026, 7, 22, 6, 30))

    expect(reminder_events(user).count).to eq(1)
  end

  it "does not continue the old plan campaign after a new active plan is created" do
    user, old_plan = build_candidate
    3.times do |index|
      create_reminder_event(user, old_plan, local_date: "2026-07-#{18 + index}", reminder_number: index + 1)
    end
    old_plan.update!(active: false)
    new_plan = user.workout_plans.create!(active: true, created_at: now - 1.hour)
    new_plan.workout_days.create!(name: "Treino B", day_of_week: 2, position: 1)

    described_class.perform_now(now: now)

    new_event = reminder_events(user).where("metadata #>> '{activation,plan_id}' = ?", new_plan.id.to_s).last
    expect(new_event).to be_present
    expect(new_event.metadata.dig("activation", "reminder_number")).to eq(1)
  end

  it "prevents duplicates when the same idempotency key is emitted twice" do
    user, = build_candidate
    result = ScheduledWorkoutReminderEligibility.new(user: user, now: now).call

    2.times do
      ScheduledWorkoutReminderEventEmitter.new(result: result, occurred_at: now).call
    end

    expect(reminder_events(user).count).to eq(1)
  end

  it "does not register events when the feature flag is disabled" do
    user, = build_candidate

    with_env("SCHEDULED_WORKOUT_REMINDER_ENABLED" => "false") do
      described_class.perform_now(now: now)
    end

    expect(reminder_events(user)).to be_empty
  end
end
