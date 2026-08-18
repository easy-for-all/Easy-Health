require "rails_helper"
require "rake"

RSpec.describe "orchestration tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("orchestration:run_15min")
  end

  let(:run_15min) { Rake::Task["orchestration:run_15min"] }
  let(:daily) { Rake::Task["orchestration:relationship_daily"] }
  let(:retry_pending_make) { Rake::Task["orchestration:retry_pending_make"] }
  let(:dispatch_deferred) { Rake::Task["orchestration:dispatch_deferred_pushes"] }

  before do
    run_15min.reenable
    daily.reenable
    retry_pending_make.reenable
    dispatch_deferred.reenable
  end

  describe "orchestration:run_15min" do
    it "runs all three producers" do
      expect(FirstWorkoutNotStarted2hJob).to receive(:perform_now).and_return({})
      expect(FirstWorkoutNotStarted24hJob).to receive(:perform_now).and_return({})
      expect(ScheduledWorkoutReminderSchedulerJob).to receive(:perform_now).and_return({})

      expect { run_15min.invoke }.to output(/orchestration:run_15min/).to_stdout
    end

    # One broken producer must not silence the other two: a single failing user
    # would otherwise stop the whole journey until somebody read the cron log.
    it "keeps running the others when one raises, then reports failure" do
      allow(FirstWorkoutNotStarted2hJob).to receive(:perform_now).and_raise(StandardError, "boom")
      expect(FirstWorkoutNotStarted24hJob).to receive(:perform_now).and_return({ events_created: 0 })
      expect(ScheduledWorkoutReminderSchedulerJob).to receive(:perform_now).and_return({ event_created: 0 })

      expect { run_15min.invoke }.to raise_error(SystemExit)
        .and output(/first_workout_not_started_2h/).to_stdout
    end

    it "exits cleanly when every producer succeeds" do
      allow(FirstWorkoutNotStarted2hJob).to receive(:perform_now).and_return({})
      allow(FirstWorkoutNotStarted24hJob).to receive(:perform_now).and_return({})
      allow(ScheduledWorkoutReminderSchedulerJob).to receive(:perform_now).and_return({})

      expect { run_15min.invoke }.not_to raise_error
    end
  end

  describe "orchestration:relationship_daily" do
    # This job ran in production only from an unversioned `rails runner` line;
    # the task is the versioned entry point that replaces it.
    it "runs the daily job" do
      expect(RelationshipDailyJob).to receive(:perform_now).and_return({ users_processed: 0 })

      expect { daily.invoke }.to output(/orchestration:relationship_daily/).to_stdout
    end
  end

  describe "orchestration:retry_pending_make" do
    it "re-drives recent pending, due retrying, and stale sending Make events" do
      user = create(:user)
      recent = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                 occurred_at: Time.current, make_delivery_status: "pending")
      old = UserEvent.create!(user: user, event_name: "first_workout_completed",
                              occurred_at: Time.current, make_delivery_status: "pending")
      old.update_columns(created_at: 2.hours.ago, updated_at: 2.hours.ago) # rubocop:disable Rails/SkipsModelValidations
      due_retrying = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                       occurred_at: Time.current, make_delivery_status: "retrying",
                                       make_next_retry_at: 1.minute.ago)
      future_retrying = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                          occurred_at: Time.current, make_delivery_status: "retrying",
                                          make_next_retry_at: 1.hour.from_now)
      stale_sending = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                        occurred_at: Time.current, make_delivery_status: "sending",
                                        make_last_attempt_at: 10.minutes.ago)
      fresh_sending = UserEvent.create!(user: user, event_name: "first_workout_completed",
                                        occurred_at: Time.current, make_delivery_status: "sending",
                                        make_last_attempt_at: 1.minute.ago)

      client = instance_double(MakeWebhookClient)
      allow(MakeWebhookClient).to receive(:new).and_return(client)
      allow(client).to receive(:deliver).and_return(MakeWebhookClient::Result.new(status: "accepted_by_make"))

      expect { retry_pending_make.invoke }.to output(/orchestration:retry_pending_make/).to_stdout

      expect(client).to have_received(:deliver).with(recent)
      expect(client).to have_received(:deliver).with(due_retrying)
      expect(client).to have_received(:deliver).with(stale_sending)
      expect(client).not_to have_received(:deliver).with(old)
      expect(client).not_to have_received(:deliver).with(future_retrying)
      expect(client).not_to have_received(:deliver).with(fresh_sending)
      expect(stale_sending.reload.make_last_error).to eq(MakePendingDeliveryRetry::ABANDONED_SENDING_ERROR)
      expect(ObservabilityHeartbeat.find_by(key: "make_pending_retry").last_succeeded_at).to be_present
    end
  end

  describe "orchestration:dispatch_deferred_pushes" do
    it "dispatches due PushDispatch rows and records heartbeat" do
      allow(Make::PushDispatchRequest).to receive(:dispatch_deferred).and_return({ sent: 1 })

      expect { dispatch_deferred.invoke }.to output(/orchestration:dispatch_deferred_pushes/).to_stdout

      expect(Make::PushDispatchRequest).to have_received(:dispatch_deferred).with(limit: 500)
      expect(ObservabilityHeartbeat.find_by(key: "push_dispatch_deferred").last_succeeded_at).to be_present
    end
  end

  describe "orchestration:status" do
    it "reports each scheduler and the catalog" do
      Rake::Task["orchestration:status"].reenable
      Observability::Heartbeat.register_all!

      expect { Rake::Task["orchestration:status"].invoke }
        .to output(a_string_including(
          "SCHEDULERS",
          "scheduled_workout_reminder",
          "make_pending_retry",
          "push_dispatch_deferred",
          "ORCHESTRATION EVENTS",
          "ALLOWLIST DRIFT",
          "PUSH_QUIET_HOURS_WINDOW"
        )).to_stdout
    end
  end
end
