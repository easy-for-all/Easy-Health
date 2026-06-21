class UserEventService
  EVENTS = %w[
    signup_completed
    trial_started
    onboarding_completed
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
  ].freeze

  def self.track(user:, event:, metadata: {})
    return unless EVENTS.include?(event.to_s)
    UserEvent.create!(user: user, event_name: event.to_s, metadata: metadata)
  rescue => e
    Rails.logger.warn("[UserEvent] Failed to track #{event} for user #{user.id}: #{e.message}")
  end
end
