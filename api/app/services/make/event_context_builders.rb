module Make
  module EventContextBuilders
    BUILDER_NAMES = {
      "workout_created_not_started" => "Make::EventContextBuilders::WorkoutCreatedNotStarted",
      "first_workout_created" => "Make::EventContextBuilders::FirstWorkoutCreated",
      "first_workout_completed" => "Make::EventContextBuilders::FirstWorkoutCompleted",
      "plan_created_but_not_used" => "Make::EventContextBuilders::PlanCreatedButNotUsed",
      "user_inactive_3_days" => "Make::EventContextBuilders::Inactivity",
      "user_inactive_7_days" => "Make::EventContextBuilders::Inactivity",
      "user_inactive_15_days" => "Make::EventContextBuilders::Inactivity"
    }.freeze

    def self.build(event)
      builder_name = BUILDER_NAMES[event.event_name.to_s]
      return {} unless builder_name

      builder_name.constantize.new(event).as_json
    end
  end
end
