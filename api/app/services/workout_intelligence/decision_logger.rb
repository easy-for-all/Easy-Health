module WorkoutIntelligence
  # Structured logging for workout generation decisions (goal/level
  # normalization, split chosen, weekly volume targets, rejected exercises,
  # substitutions, validation results). Backend-only for now — no admin UI.
  class DecisionLogger
    def self.log(event:, user_id:, plan_id: nil, **payload)
      Rails.logger.info(
        {
          component: "workout_intelligence",
          event: event,
          user_id: user_id,
          plan_id: plan_id,
          **payload
        }.to_json
      )
    end
  end
end
