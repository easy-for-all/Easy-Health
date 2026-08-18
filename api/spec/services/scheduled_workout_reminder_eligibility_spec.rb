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

  describe "inactivity suppression" do
    # The policy is paused by default; these examples describe it turned on.
    around { |ex| with_env("SCHEDULED_WORKOUT_INACTIVITY_SUPPRESSION_ENABLED" => "true") { ex.run } }

    it "allows reminders when the last completed workout is 4d23h59 ago" do
      user, = build_candidate
      user.workout_sessions.create!(
        status: "completed",
        completion_status: "completed",
        completed_at: now - 5.days + 1.minute,
        duration_minutes: 30
      )

      result = result_for(user)

      expect(result).to be_eligible
      expect(user.health_profile.reload.scheduled_workout_reminder_suppressed_at).to be_nil
    end

    it "suppresses reminders when the last completed workout is exactly 5 days ago" do
      user, = build_candidate
      user.workout_sessions.create!(
        status: "completed",
        completion_status: "completed",
        completed_at: now - 5.days,
        duration_minutes: 30
      )

      result = result_for(user)

      expect(result).not_to be_eligible
      expect(result.reason).to eq("inactive_5_days")
      expect(user.health_profile.reload.scheduled_workout_reminder_suppression_reason).to eq("inactive_5_days")
    end

    it "suppresses reminders when the last completed workout is 8 days ago" do
      user, = build_candidate
      user.workout_sessions.create!(
        status: "completed",
        completion_status: "completed",
        completed_at: now - 8.days,
        duration_minutes: 30
      )

      result = result_for(user)

      expect(result).not_to be_eligible
      expect(result.reason).to eq("inactive_5_days")
    end

    it "does not suppress users who never completed a workout" do
      user, = build_candidate

      result = result_for(user)

      expect(result).to be_eligible
      expect(user.health_profile.reload.scheduled_workout_reminder_suppressed_at).to be_nil
    end
  end

  describe "inactivity suppression paused" do
    around { |ex| with_env("SCHEDULED_WORKOUT_INACTIVITY_SUPPRESSION_ENABLED" => "false") { ex.run } }

    it "stays eligible after eight days without a completed workout" do
      user, = build_candidate
      user.workout_sessions.create!(
        status: "completed",
        completion_status: "completed",
        completed_at: now - 8.days,
        duration_minutes: 30
      )

      result = result_for(user)

      expect(result).to be_eligible
      expect(user.health_profile.reload.scheduled_workout_reminder_suppressed_at).to be_nil
      expect(user.user_events.where(event_name: "scheduled_workout_reminder_suppressed")).to be_empty
    end

    it "stays eligible when an inactivity suppression is already persisted" do
      user, = build_candidate
      user.health_profile.update_columns( # rubocop:disable Rails/SkipsModelValidations
        scheduled_workout_reminder_suppressed_at: now - 10.days,
        scheduled_workout_reminder_suppression_reason: ScheduledWorkoutReminderSuppression::REASON
      )

      expect(result_for(user)).to be_eligible
    end
  end

  it "rejects variable schedules" do
    user, = build_candidate(period: "variable", preferred_time: nil)

    expect(result_for(user).reason).to eq("variable_schedule")
  end

  it "falls back to the communication timezone for missing and invalid timezone values" do
    missing_tz, = build_candidate(timezone: nil)
    invalid_tz, = build_candidate(timezone: "Mars/Olympus")

    expect(result_for(missing_tz)).to be_eligible
    expect(result_for(missing_tz).schedule.timezone).to eq("America/Sao_Paulo")
    expect(result_for(invalid_tz)).to be_eligible
    expect(result_for(invalid_tz).schedule.timezone).to eq("America/Sao_Paulo")
  end

  # "The user asked to train at 07:00 and it is 06:30" is a fact about the
  # user's plan, not about their push settings. Those settings are re-checked at
  # dispatch, where they are still true when Make actually asks; blocking the
  # event here lost the fact for exactly the people a reminder should reach.
  describe "communication settings do not block the event" do
    it "stays eligible with push disabled" do
      user, = build_candidate
      user.notification_preferences.update!(push_enabled: false)

      expect(result_for(user)).to be_eligible
    end

    it "stays eligible with workout reminders disabled" do
      user, = build_candidate
      user.notification_preferences.update!(workout_reminders_enabled: false)

      expect(result_for(user)).to be_eligible
    end

    it "stays eligible with no granted device token" do
      user, = build_candidate
      user.device_tokens.update_all(permission_status: "denied") # rubocop:disable Rails/SkipsModelValidations

      expect(result_for(user)).to be_eligible
    end

    it "stays eligible with no preferences row at all" do
      user, = build_candidate
      user.notification_preferences.destroy!
      user.reload

      expect(result_for(user)).to be_eligible
    end

    it "stays eligible with the legacy env allowlist empty" do
      user, = build_candidate

      with_env("MAKE_WEBHOOK_ALLOWED_EVENTS" => "") do
        expect(result_for(user)).to be_eligible
      end
    end
  end

  it "rejects a deleted or anonymized account" do
    deleted, = build_candidate
    deleted.update!(deletion_requested_at: Time.current)

    anonymized, = build_candidate
    anonymized.update!(anonymized_at: Time.current)

    expect(result_for(deleted).reason).to eq("user_deleted_or_anonymized")
    expect(result_for(anonymized).reason).to eq("user_deleted_or_anonymized")
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

  # The product rule is reminder_due_at = preferred_workout_time - lead_time.
  # The scheduler's tolerance window only decides how LATE a due moment may
  # still be picked up; it must never make a reminder fire early.
  describe "the due moment" do
    it "does not fire before the lead time, even inside the window" do
      user, = build_candidate(preferred_time: "07:10") # due 06:40

      expect(result_for(user, at: zone.local(2026, 7, 21, 6, 30))).not_to be_eligible
    end

    it "fires late rather than not at all when a tick straddles the due moment" do
      user, = build_candidate(preferred_time: "07:10") # due 06:40

      result = result_for(user, at: zone.local(2026, 7, 21, 6, 45))

      expect(result).to be_eligible
      expect(result.schedule.reminder_time).to eq("06:40")
    end

    # With a 15min cron, a 10min window let a due moment fall between two ticks
    # and vanish. The window must cover the whole gap.
    it "still catches a reminder due 14 minutes ago" do
      user, = build_candidate(preferred_time: "07:00") # due 06:30

      expect(result_for(user, at: zone.local(2026, 7, 21, 6, 44))).to be_eligible
    end

    it "honours a configured lead time" do
      user, = build_candidate(preferred_time: "07:00")

      with_env("SCHEDULED_WORKOUT_REMINDER_LEAD_MINUTES" => "45") do
        result = result_for(user, at: zone.local(2026, 7, 21, 6, 15))

        expect(result).to be_eligible
        expect(result.schedule.reminder_time).to eq("06:15")
        expect(result.schedule.reminder_lead_minutes).to eq(45)
      end
    end

    it "resolves the due moment in the user's own timezone" do
      user, = build_candidate(preferred_time: "07:00")
      user.update!(time_zone: "Europe/Lisbon")

      lisbon_due = ActiveSupport::TimeZone["Europe/Lisbon"].local(2026, 7, 21, 6, 30)

      expect(result_for(user, at: lisbon_due)).to be_eligible
      expect(result_for(user, at: zone.local(2026, 7, 21, 6, 30))).not_to be_eligible
    end
  end
end
