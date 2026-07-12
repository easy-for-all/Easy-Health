# Activation push sweeps, driven by external cron on the VPS (mirrors
# activation_reminders.rake). All run synchronously via perform_now.
#
# Suggested cron (every 15 min):
#   */15 * * * * cd /path/api && bin/rails push_activation:run_reminders
#   */15 * * * * cd /path/api && bin/rails push_activation:run_recovery
#   */15 * * * * cd /path/api && bin/rails push_activation:dispatch_due
namespace :push_activation do
  desc "Schedule first-workout reminder pushes for eligible users"
  task run_reminders: :environment do
    stats = FirstWorkoutReminderEligibilityJob.perform_now
    puts "[push_activation:run_reminders] #{stats.inspect}"
  end

  desc "Schedule first-workout recovery pushes for eligible users"
  task run_recovery: :environment do
    stats = FirstWorkoutRecoveryEligibilityJob.perform_now
    puts "[push_activation:run_recovery] #{stats.inspect}"
  end

  desc "Send all scheduled pushes whose time has arrived"
  task dispatch_due: :environment do
    stats = DispatchDuePushJob.perform_now
    puts "[push_activation:dispatch_due] #{stats.inspect}"
  end
end
