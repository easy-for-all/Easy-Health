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
  let(:zone) { ActiveSupport::TimeZone["America/Sao_Paulo"] }
  let(:now) { zone.local(2026, 7, 21, 6, 30) }
  let(:make_env) { scheduled_reminder_make_env }

  before do
    run_task.reenable
    manual_task.reenable
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
end
