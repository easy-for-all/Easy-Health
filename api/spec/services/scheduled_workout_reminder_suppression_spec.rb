require "rails_helper"

RSpec.describe ScheduledWorkoutReminderSuppression do
  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
  let(:now) { zone.local(2026, 7, 21, 6, 30) }
  let(:user) { create(:user, time_zone: "America/Sao_Paulo") }
  let(:profile) do
    create(:health_profile, user: user, preferred_workout_period: "morning", preferred_workout_time: "07:00")
  end
  let(:schedule) { instance_double(ScheduledWorkoutReminderSchedule::Result, preferred_workout_time: "07:00") }

  # Every example below describes the ACTIVE policy, which is paused by default
  # now. Turning it on explicitly keeps them honest instead of adjusting the
  # expectations to the paused behaviour.
  around { |ex| with_env("SCHEDULED_WORKOUT_INACTIVITY_SUPPRESSION_ENABLED" => "true") { ex.run } }

  before do
    profile
    allow(MakeWebhookDeliveryJob).to receive(:perform_later)
  end

  def service(at: now)
    described_class.new(user: user, health_profile: profile, now: at)
  end

  def complete_workout!(at:)
    user.workout_sessions.create!(
      status: "completed",
      completion_status: "completed",
      completed_at: at,
      duration_minutes: 30
    )
  end

  def suppressed_events
    user.user_events.where(event_name: described_class::SUPPRESSED_EVENT_NAME)
  end

  def resumed_events
    user.user_events.where(event_name: described_class::RESUMED_EVENT_NAME)
  end

  it "suppresses once and keeps users without notification preferences untouched" do
    complete_workout!(at: now - 5.days)

    result = service.suppress_if_needed!(schedule: schedule)

    expect(result).to be_suppressed
    expect(result).to be_transitioned
    expect(profile.reload.scheduled_workout_reminder_suppression_reason).to eq("inactive_5_days")
    expect(profile.scheduled_workout_reminder_suppression_metadata).to include(
      "threshold_days" => 5,
      "preferred_workout_time" => "07:00"
    )
    expect(user.reload.notification_preferences).to be_nil
    expect(suppressed_events.count).to eq(1)
  end

  it "does not suppress a user who never completed a workout" do
    result = service.suppress_if_needed!(schedule: schedule)

    expect(result).not_to be_suppressed
    expect(profile.reload.scheduled_workout_reminder_suppressed_at).to be_nil
    expect(suppressed_events).to be_empty
  end

  it "emits at most one suppressed event for the same active to suppressed transition" do
    complete_workout!(at: now - 8.days)

    2.times { service.suppress_if_needed!(schedule: schedule) }

    expect(suppressed_events.count).to eq(1)
  end

  it "marks suppressed events as producer-suppressed and never enqueues Make" do
    complete_workout!(at: now - 8.days)

    event = service.suppress_if_needed!(schedule: schedule).event

    expect(event.reload.make_delivery_status).to eq("disabled")
    expect(event.make_last_error).to eq("suppressed_by_producer")
    expect(MakeWebhookDeliveryJob).not_to have_received(:perform_later)
  end

  it "does not resume without a completed workout after suppressed_at" do
    complete_workout!(at: now - 8.days)
    service.suppress_if_needed!(schedule: schedule)

    2.times { service.resume_if_needed! }

    expect(profile.reload.scheduled_workout_reminder_suppressed_at).to be_present
    expect(resumed_events).to be_empty
  end

  it "resumes once when a workout was completed after suppressed_at without creating preferences" do
    complete_workout!(at: now - 8.days)
    service.suppress_if_needed!(schedule: schedule)
    complete_workout!(at: now + 1.hour)

    2.times { service(at: now + 2.hours).resume_if_needed! }

    expect(profile.reload.scheduled_workout_reminder_suppressed_at).to be_nil
    expect(profile.scheduled_workout_reminder_suppression_reason).to be_nil
    expect(profile.scheduled_workout_reminder_suppression_metadata).to eq({})
    expect(user.reload.notification_preferences).to be_nil
    expect(resumed_events.count).to eq(1)
  end

  it "does not change notification preference flags when resuming" do
    user.notification_preferences!.update!(
      push_enabled: false,
      workout_reminders_enabled: false,
      workout_ready_enabled: false,
      max_pushes_per_week: 0,
      notifications_disabled_at: now - 1.day,
      disabled_reason: "user_settings"
    )
    complete_workout!(at: now - 8.days)
    service.suppress_if_needed!(schedule: schedule)
    complete_workout!(at: now + 1.hour)

    service(at: now + 2.hours).resume_if_needed!

    prefs = user.notification_preferences.reload
    expect(prefs.push_enabled).to be(false)
    expect(prefs.workout_reminders_enabled).to be(false)
    expect(prefs.workout_ready_enabled).to be(false)
    expect(prefs.max_pushes_per_week).to eq(0)
    expect(prefs.notifications_disabled_at).to be_present
    expect(prefs.disabled_reason).to eq("user_settings")
  end

  it "marks resumed events as producer-suppressed and never enqueues Make" do
    complete_workout!(at: now - 8.days)
    service.suppress_if_needed!(schedule: schedule)
    complete_workout!(at: now + 1.hour)

    event = service(at: now + 2.hours).resume_if_needed!.event

    expect(event.reload.make_delivery_status).to eq("disabled")
    expect(event.make_last_error).to eq("suppressed_by_producer")
    expect(MakeWebhookDeliveryJob).not_to have_received(:perform_later)
  end

  it "allows a new suppressed transition after a resume and another five inactive days" do
    complete_workout!(at: now - 8.days)
    service.suppress_if_needed!(schedule: schedule)
    completed_after_suppression = now + 1.hour
    complete_workout!(at: completed_after_suppression)
    service(at: now + 2.hours).resume_if_needed!

    service(at: completed_after_suppression + 5.days).suppress_if_needed!(schedule: schedule)

    expect(suppressed_events.count).to eq(2)
  end

  describe "with the inactivity policy paused" do
    around { |ex| with_env("SCHEDULED_WORKOUT_INACTIVITY_SUPPRESSION_ENABLED" => "false") { ex.run } }

    def persist_suppression!(reason:, at: now - 10.days)
      profile.update_columns( # rubocop:disable Rails/SkipsModelValidations
        scheduled_workout_reminder_suppressed_at: at,
        scheduled_workout_reminder_suppression_reason: reason,
        scheduled_workout_reminder_suppression_metadata: { "reason" => reason }
      )
    end

    it "does not suppress a user inactive for more than five days" do
      complete_workout!(at: now - 8.days)

      result = service.suppress_if_needed!(schedule: schedule)

      expect(result).not_to be_suppressed
      expect(result).not_to be_transitioned
      expect(profile.reload.scheduled_workout_reminder_suppressed_at).to be_nil
      expect(suppressed_events).to be_empty
    end

    it "ignores an inactivity suppression already on the row without rewriting it" do
      persist_suppression!(reason: described_class::REASON)
      complete_workout!(at: now - 20.days)

      result = service.suppress_if_needed!(schedule: schedule)

      expect(result).not_to be_suppressed
      expect(profile.reload.scheduled_workout_reminder_suppressed_at).to eq(now - 10.days)
      expect(profile.scheduled_workout_reminder_suppression_reason).to eq(described_class::REASON)
      expect(profile.scheduled_workout_reminder_suppression_metadata).to eq("reason" => described_class::REASON)
      expect(suppressed_events).to be_empty
    end

    it "still honours a suppression reason belonging to another policy" do
      persist_suppression!(reason: "other_policy")

      expect(service.suppress_if_needed!(schedule: schedule)).to be_suppressed
    end

    it "makes resume a no-op: no write, no event" do
      persist_suppression!(reason: described_class::REASON)
      complete_workout!(at: now - 1.hour)

      result = service.resume_if_needed!

      expect(result).not_to be_transitioned
      expect(profile.reload.scheduled_workout_reminder_suppressed_at).to eq(now - 10.days)
      expect(profile.scheduled_workout_reminder_suppression_reason).to eq(described_class::REASON)
      expect(resumed_events).to be_empty
    end
  end
end
