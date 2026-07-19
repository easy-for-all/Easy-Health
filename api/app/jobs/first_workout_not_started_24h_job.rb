# Candidates: created the first plan 24–48h ago and still haven't started a
# workout. Run every ~15min via the external scheduler (lib/tasks/push_journey.rake).
class FirstWorkoutNotStarted24hJob < FirstWorkoutNotStartedJob
  private

  def event_name
    "first_workout_not_started_24h"
  end

  def window_range
    48.hours.ago..24.hours.ago
  end
end
