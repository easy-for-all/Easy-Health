class UserEventService
  EVENTS = %w[
    signup_completed
    trial_started
    onboarding_completed
    fitness_profile_created
    fitness_profile_recalculated
    persona_classified
    training_archetype_classified
    behavior_pattern_updated
    workout_created
    workout_started
    workout_completed
    progress_viewed
    favorite_added
    photo_uploaded
    exam_uploaded
    bioimpedance_added
    paywall_viewed
    checkout_started
    subscription_created
    trial_expired
    workout_strategy_created
    ai_workout_generated
    ai_workout_validation_failed
    coach_insight_created
    exercise_favorited
    exercise_skipped
    exercise_substituted
    bioimpedance_added
  ].freeze

  def self.track(user:, event:, metadata: {})
    return unless EVENTS.include?(event.to_s)
    UserEvent.create!(user: user, event_name: event.to_s, metadata: metadata)
  rescue => e
    Rails.logger.warn("[UserEvent] Failed to track #{event} for user #{user.id}: #{e.message}")
  end
end
