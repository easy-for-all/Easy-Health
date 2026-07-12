module ActivationPushHelper
  # Builds a user that satisfies every reminder-eligibility rule.
  def build_eligible_push_user(period: "evening", time: "19:00")
    user = create(:user)
    user.update!(time_zone: "America/Sao_Paulo")
    create(:health_profile, user: user, preferred_workout_period: period, preferred_workout_time: time)
    user.workout_plans.create!
    user.device_tokens.create!(token: "tok-#{SecureRandom.hex(6)}", platform: "android")
    user.notification_preferences!.update!(push_enabled: true, workout_reminders_enabled: true)
    user
  end
end

RSpec.configure do |config|
  config.include ActivationPushHelper
end
