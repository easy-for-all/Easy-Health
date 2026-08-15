# Candidates: created the first plan 24–48h ago and still haven't started a
# workout. Run every ~15min from cron (bin/rails orchestration:run_15min).
class FirstWorkoutNotStarted24hJob < FirstWorkoutNotStartedJob
  def self.observability_heartbeat_key = "first_workout_not_started_24h"

  private

  def event_name
    "first_workout_not_started_24h"
  end

  def window_range
    48.hours.ago..24.hours.ago
  end
end
