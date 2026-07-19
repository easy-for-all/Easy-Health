# Candidates: created the first plan 2–26h ago and still haven't started a
# workout. Run every ~15min via the external scheduler (lib/tasks/push_journey.rake).
class FirstWorkoutNotStarted2hJob < FirstWorkoutNotStartedJob
  private

  def event_name
    "first_workout_not_started_2h"
  end

  def window_range
    26.hours.ago..2.hours.ago
  end
end
