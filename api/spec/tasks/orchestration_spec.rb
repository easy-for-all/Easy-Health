require "rails_helper"
require "rake"

RSpec.describe "orchestration tasks" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("orchestration:run_15min")
  end

  let(:run_15min) { Rake::Task["orchestration:run_15min"] }
  let(:daily) { Rake::Task["orchestration:relationship_daily"] }

  before do
    run_15min.reenable
    daily.reenable
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

  describe "orchestration:status" do
    it "reports each scheduler and the catalog" do
      Rake::Task["orchestration:status"].reenable
      Observability::Heartbeat.register_all!

      expect { Rake::Task["orchestration:status"].invoke }
        .to output(/SCHEDULERS.*scheduled_workout_reminder.*ORCHESTRATION EVENTS.*ALLOWLIST DRIFT/m).to_stdout
    end
  end
end
