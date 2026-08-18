require "rails_helper"
require "rake"

RSpec.describe "scheduled workout reminder tasks" do
  scheduled_reminder_make_env = {
    "SCHEDULED_WORKOUT_REMINDER_ENABLED" => "true",
    "MAKE_WEBHOOK_ENABLED" => "true",
    "MAKE_WEBHOOK_URL" => "https://make.example/webhook",
    "MAKE_WEBHOOK_SECRET" => "secret",
    "MAKE_WEBHOOK_ALLOWED_EVENTS" => "scheduled_workout_reminder_due",
    "MAKE_EVENT_SCHEMA_VERSION" => "2"
  }.freeze

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("scheduled_workout_reminders:run")
  end

  let(:run_task) { Rake::Task["scheduled_workout_reminders:run"] }
  let(:manual_task) { Rake::Task["scheduled_workout_reminders:manual_test"] }
  let(:clear_task) { Rake::Task["scheduled_workout_reminders:clear_inactivity_suppressions"] }
  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
  let(:now) { zone.local(2026, 7, 21, 6, 30) }
  let(:make_env) { scheduled_reminder_make_env }

  before do
    run_task.reenable
    manual_task.reenable
    clear_task.reenable
    allow(MakeWebhookDeliveryJob).to receive(:perform_later)
  end

  def build_candidate(admin: false)
    user = admin ? create(:user, :admin, marketing_consent: true, time_zone: "America/Sao_Paulo") :
                   create(:user, marketing_consent: true, time_zone: "America/Sao_Paulo")
    create(:health_profile, user: user, preferred_workout_period: "morning", preferred_workout_time: "07:00")
    plan = user.workout_plans.create!(active: true)
    plan.update_columns(created_at: now - 1.day, updated_at: now - 1.day) # rubocop:disable Rails/SkipsModelValidations
    plan.workout_days.create!(name: "Treino A", day_of_week: 1, position: 1)
    create(:device_token, user: user, permission_status: "granted")
    user.notification_preferences!.update!(push_enabled: true, workout_reminders_enabled: true)
    user
  end

  it "runs the sweep scoped by USER_ID and NOW" do
    user = build_candidate

    with_env(make_env.merge("USER_ID" => user.id.to_s, "NOW" => "2026-07-21T06:30:00-03:00")) do
      expect do
        expect { run_task.invoke }.to output(/scheduled_workout_reminders:run/).to_stdout
      end.to change(user.user_events.where(event_name: "scheduled_workout_reminder_due"), :count).by(1)
    end
  end

  it "creates a manual admin test event with the manual campaign" do
    admin = build_candidate(admin: true)

    with_env(make_env.merge("NOW" => "2026-07-21T06:30:00-03:00")) do
      expect do
        expect { manual_task.invoke(admin.email) }
          .to output(/first_workout_scheduled_reminder_manual_test/).to_stdout
      end.to change(admin.user_events.where(event_name: "scheduled_workout_reminder_due"), :count).by(1)
    end

    event = admin.user_events.where(event_name: "scheduled_workout_reminder_due").last
    expect(event.source).to eq("manual_test")
    expect(event.metadata["campaign"]).to eq("first_workout_scheduled_reminder_manual_test")
    expect(event.idempotency_key).to include("scheduled-workout-reminder-manual-test")
  end

  describe "clear_inactivity_suppressions" do
    def suppressed_profile(reason:)
      profile = create(:health_profile, preferred_workout_period: "morning", preferred_workout_time: "07:00")
      profile.update_columns( # rubocop:disable Rails/SkipsModelValidations
        scheduled_workout_reminder_suppressed_at: 3.days.ago,
        scheduled_workout_reminder_suppression_reason: reason,
        scheduled_workout_reminder_suppression_metadata: { "reason" => reason },
        workout_time_source: "onboarding",
        preferred_workout_time_updated_at: 10.days.ago
      )
      profile
    end

    def pretend_production!
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    end

    it "clears only the inactivity suppressions" do
      inactive_one = suppressed_profile(reason: ScheduledWorkoutReminderSuppression::REASON)
      inactive_two = suppressed_profile(reason: ScheduledWorkoutReminderSuppression::REASON)
      other_policy = suppressed_profile(reason: "other_policy")
      untouched = create(:health_profile, preferred_workout_period: "morning", preferred_workout_time: "07:00")

      with_env("DRY_RUN" => "false") do
        expect { clear_task.invoke }.to output(/dry_run=false found=2 cleared=2/).to_stdout
      end

      [ inactive_one, inactive_two ].each do |profile|
        profile.reload
        expect(profile.scheduled_workout_reminder_suppressed_at).to be_nil
        expect(profile.scheduled_workout_reminder_suppression_reason).to be_nil
        expect(profile.scheduled_workout_reminder_suppression_metadata).to eq({})
      end

      expect(other_policy.reload.scheduled_workout_reminder_suppression_reason).to eq("other_policy")
      expect(other_policy.scheduled_workout_reminder_suppressed_at).to be_present
      expect(untouched.reload.scheduled_workout_reminder_suppressed_at).to be_nil
    end

    it "leaves schedule preferences and notification opt-outs untouched" do
      profile = suppressed_profile(reason: ScheduledWorkoutReminderSuppression::REASON)
      disabled_at = 2.days.ago
      profile.user.notification_preferences!.update!(
        push_enabled: false,
        workout_reminders_enabled: false,
        notifications_disabled_at: disabled_at,
        disabled_reason: "user_settings"
      )

      with_env("DRY_RUN" => "false") { clear_task.invoke }

      profile.reload
      expect(profile.scheduled_workout_reminder_suppression_reason).to be_nil
      expect(profile.preferred_workout_time.strftime("%H:%M")).to eq("07:00")
      expect(profile.workout_time_source).to eq("onboarding")
      expect(profile.preferred_workout_time_updated_at).to be_present

      prefs = profile.user.notification_preferences.reload
      expect(prefs.push_enabled).to be(false)
      expect(prefs.workout_reminders_enabled).to be(false)
      expect(prefs.notifications_disabled_at).to be_present
      expect(prefs.disabled_reason).to eq("user_settings")
    end

    it "is a dry run when DRY_RUN is not given" do
      profile = suppressed_profile(reason: ScheduledWorkoutReminderSuppression::REASON)

      expect { clear_task.invoke }.to output(/dry_run=true found=1 cleared=0/).to_stdout

      expect(profile.reload.scheduled_workout_reminder_suppression_reason)
        .to eq(ScheduledWorkoutReminderSuppression::REASON)
      expect(profile.scheduled_workout_reminder_suppressed_at).to be_present
    end

    it "refuses to write in production without the explicit confirmation" do
      profile = suppressed_profile(reason: ScheduledWorkoutReminderSuppression::REASON)
      pretend_production!

      with_env("DRY_RUN" => "false") do
        expect { clear_task.invoke }.to raise_error(SystemExit)
      end

      expect(profile.reload.scheduled_workout_reminder_suppression_reason)
        .to eq(ScheduledWorkoutReminderSuppression::REASON)
    end

    it "writes in production once the confirmation is given" do
      profile = suppressed_profile(reason: ScheduledWorkoutReminderSuppression::REASON)
      pretend_production!

      confirmation = {
        "DRY_RUN" => "false",
        "CONFIRM_PRODUCTION_SCHEDULED_WORKOUT_INACTIVITY_CLEAR" => "true"
      }
      with_env(confirmation) do
        expect { clear_task.invoke }.to output(/found=1 cleared=1/).to_stdout
      end

      expect(profile.reload.scheduled_workout_reminder_suppression_reason).to be_nil
    end
  end
end
