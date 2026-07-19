# Push journey V1 eligibility sweeps. Run via external cron every ~15min.
# These only EMIT UserEvents (delivered to Make); they never send push directly.
# Inactivity (3d/7d) is emitted by the daily relationship job.
namespace :push_journey do
  desc "Emit first_workout_not_started_2h for users who created a plan 2-26h ago and haven't started"
  task first_workout_not_started_2h: :environment do
    stats = FirstWorkoutNotStarted2hJob.perform_now
    puts "[push_journey:first_workout_not_started_2h] #{stats.inspect}"
  end

  desc "Emit first_workout_not_started_24h for users who created a plan 24-48h ago and haven't started"
  task first_workout_not_started_24h: :environment do
    stats = FirstWorkoutNotStarted24hJob.perform_now
    puts "[push_journey:first_workout_not_started_24h] #{stats.inspect}"
  end
end
