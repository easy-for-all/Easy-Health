require "rails_helper"

RSpec.describe ScheduledWorkoutReminderEligibility do
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

  def build_candidate(preferred_time: "07:00", period: "morning", timezone: "America/Sao_Paulo", plan_created_at: nil)
    plan_created_at ||= now - 1.day
    user = create(:user, marketing_consent: true, time_zone: timezone)
    create(:health_profile, user: user, preferred_workout_period: period, preferred_workout_time: preferred_time)
    plan = user.workout_plans.create!(active: true)
    plan.update_columns(created_at: plan_created_at, updated_at: plan_created_at) # rubocop:disable Rails/SkipsModelValidations
    day = plan.workout_days.create!(name: "Treino A", day_of_week: 1, position: 1)
    create(:device_token, user: user, permission_status: "granted")
    user.notification_preferences!.update!(push_enabled: true, workout_reminders_enabled: true)
    [ user, plan, day ]
  end

  def result_for(user, at: now)
    described_class.new(user: user, now: at).call
  end

  it "is eligible when a 07:00 preference is due at 06:30 local time" do
    user, plan, day = build_candidate

    result = result_for(user)

    expect(result).to be_eligible
    expect(result.reason).to eq("eligible")
    expect(result.plan).to eq(plan)
    expect(result.workout_id).to eq(day.id)
    expect(result.schedule.reminder_time).to eq("06:30")
    expect(result.schedule.reminder_local_date).to eq("2026-07-21")
    expect(result.reminder_number).to eq(1)
  end

  it "is not eligible at 06:29 for a 07:00 preference" do
    user, = build_candidate

    result = result_for(user, at: zone.local(2026, 7, 21, 6, 29))

    expect(result).not_to be_eligible
    expect(result.reason).to eq("outside_window")
  end

  it "stops when the user completed a valid workout for the current plan" do
    user, _plan, day = build_candidate
    user.workout_sessions.create!(
      workout_day: day,
      status: "completed",
      completion_status: "completed",
      completed_at: now - 1.hour,
      duration_minutes: 30
    )

    expect(result_for(user).reason).to eq("workout_completed")
  end

  it "does not stop only because a workout was started" do
    user, _plan, day = build_candidate
    user.workout_sessions.create!(workout_day: day, status: "in_progress")

    expect(result_for(user)).to be_eligible
  end

  it "rejects variable schedules" do
    user, = build_candidate(period: "variable", preferred_time: nil)

    expect(result_for(user).reason).to eq("variable_schedule")
  end

  it "rejects missing and invalid timezone values" do
    missing_tz, = build_candidate(timezone: nil)
    invalid_tz, = build_candidate(timezone: "Mars/Olympus")

    expect(result_for(missing_tz).reason).to eq("missing_timezone")
    expect(result_for(invalid_tz).reason).to eq("invalid_timezone")
  end

  it "rejects disabled push or missing granted device tokens" do
    push_disabled, = build_candidate
    push_disabled.notification_preferences.update!(push_enabled: false)

    denied_device, = build_candidate
    denied_device.device_tokens.update_all(permission_status: "denied") # rubocop:disable Rails/SkipsModelValidations

    expect(result_for(push_disabled).reason).to eq("push_disabled")
    expect(result_for(denied_device).reason).to eq("no_active_device_token")
  end

  it "rejects a candidate with no preferences row (stays blocked)" do
    user, = build_candidate
    user.notification_preferences.destroy!
    user.reload

    expect(result_for(user).reason).to eq("push_disabled")
  end

  it "rejects a missing current plan" do
    user, plan = build_candidate
    plan.destroy!

    expect(result_for(user).reason).to eq("missing_plan")
  end

  it "does not emit for today's slot when the plan was created after the reminder time" do
    user, = build_candidate(plan_created_at: zone.local(2026, 7, 21, 6, 31))

    result = result_for(user, at: zone.local(2026, 7, 21, 6, 35))

    expect(result).not_to be_eligible
    expect(result.reason).to eq("plan_created_after_reminder")
  end

  it "uses the previous local date for a 00:15 workout reminder at 23:45" do
    user, = build_candidate(preferred_time: "00:15", period: "morning", plan_created_at: zone.local(2026, 7, 20, 12, 0))

    result = result_for(user, at: zone.local(2026, 7, 20, 23, 45))

    expect(result).to be_eligible
    expect(result.schedule.preferred_workout_time).to eq("00:15")
    expect(result.schedule.reminder_time).to eq("23:45")
    expect(result.schedule.reminder_local_date).to eq("2026-07-20")
  end

  it "calculates due windows in the user's timezone, not the server timezone" do
    new_york = ActiveSupport::TimeZone["America/New_York"]
    user, = build_candidate(timezone: "America/New_York", plan_created_at: new_york.local(2026, 1, 9, 9, 0))

    result = result_for(user, at: Time.utc(2026, 1, 10, 11, 30))

    expect(result).to be_eligible
    expect(result.schedule.timezone).to eq("America/New_York")
    expect(result.schedule.reminder_time).to eq("06:30")
  end

  it "stops at three registered reminders for the current plan" do
    user, plan = build_candidate
    3.times do |index|
      user.user_events.create!(
        event_name: "scheduled_workout_reminder_due",
        occurred_at: now - (index + 1).days,
        metadata: {
          campaign: described_class::CAMPAIGN,
          activation: { plan_id: plan.id, reminder_local_date: (now.to_date - index - 1).iso8601 }
        }
      )
    end

    expect(result_for(user).reason).to eq("maximum_reached")
  end

  it "does not count manual-test campaign events against the real campaign" do
    user, plan = build_candidate
    user.user_events.create!(
      event_name: "scheduled_workout_reminder_due",
      occurred_at: now - 1.day,
      metadata: {
        campaign: described_class::MANUAL_CAMPAIGN,
        activation: { plan_id: plan.id, reminder_local_date: now.to_date.iso8601 }
      }
    )

    expect(result_for(user)).to be_eligible
  end

  it "blocks the scheduler when the feature flag is off" do
    user, = build_candidate

    with_env("SCHEDULED_WORKOUT_REMINDER_ENABLED" => "false") do
      expect(result_for(user).reason).to eq("feature_disabled")
    end
  end
end
