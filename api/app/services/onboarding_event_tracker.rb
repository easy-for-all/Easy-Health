class OnboardingEventTracker
  def self.track(user:, event_name:, onboarding_flow: nil, step_name: nil, metadata: {}, occurred_at: nil)
    new(user: user, event_name: event_name, onboarding_flow: onboarding_flow, step_name: step_name,
        metadata: metadata, occurred_at: occurred_at).track
  end

  def initialize(user:, event_name:, onboarding_flow: nil, step_name: nil, metadata: {}, occurred_at: nil)
    @user = user
    @event_name = event_name.to_s
    @onboarding_flow = onboarding_flow.presence
    @step_name = step_name.presence
    @metadata = metadata.is_a?(Hash) ? metadata : {}
    @occurred_at = occurred_at || Time.current
  end

  def track
    return unless @user
    return unless OnboardingEvent::EVENT_NAMES.include?(@event_name)
    return unless @onboarding_flow.nil? || OnboardingEvent::FLOWS.include?(@onboarding_flow)

    event = OnboardingEvent.create!(
      user: @user,
      event_name: @event_name,
      onboarding_flow: @onboarding_flow,
      step_name: @step_name,
      metadata: @metadata,
      occurred_at: @occurred_at
    )

    attribute_flow! if @event_name == "onboarding_flow_selected"

    event
  rescue StandardError => e
    Rails.logger.warn("[OnboardingEventTracker] failed to track #{@event_name.inspect} for user=#{@user&.id}: #{e.class}: #{e.message}")
    nil
  end

  private

  def attribute_flow!
    return unless @onboarding_flow
    return unless @user.onboarding_flow.nil?

    @user.update_column(:onboarding_flow, @onboarding_flow)
  end
end
