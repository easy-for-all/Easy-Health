# Fixed activation-push copy (NO AI). Personalization is limited to the declared
# workout time and the journey stage (reminder vs recovery), per the MVP scope.
class ActivationPushMessages
  # Frontend route the deep link opens. The client re-validates this against an
  # allowlist before navigating — never trust it blindly.
  DEFAULT_TARGET_PATH = "/workouts/ready".freeze

  def self.build(notification_type:, user:, delivery: nil)
    new(notification_type:, user:, delivery:).build
  end

  def initialize(notification_type:, user:, delivery: nil)
    @notification_type = notification_type
    @user = user
    @delivery = delivery
  end

  def build
    { title:, body:, data: }
  end

  private

  attr_reader :notification_type, :user, :delivery

  def title
    case notification_type
    when "first_workout_reminder" then "Seu treino está pronto 💪"
    when "first_workout_recovery" then "Seu primeiro treino continua te esperando"
    else "Seu treino está pronto 💪"
    end
  end

  def body
    case notification_type
    when "first_workout_reminder"
      if formatted_time
        "Você marcou que costuma treinar por volta das #{formatted_time}. Que tal começar hoje?"
      else
        "Que tal começar seu primeiro treino agora? É rápido para dar o primeiro passo."
      end
    when "first_workout_recovery"
      "Não precisa fazer tudo perfeito. Comece pelo primeiro exercício e veja como se sente."
    else
      "Que tal começar seu primeiro treino agora?"
    end
  end

  def data
    {
      notification_type: notification_type,
      target_type: "workout_plan",
      target_id: active_plan_id,
      target_path: DEFAULT_TARGET_PATH,
      delivery_id: delivery&.id
    }.compact
  end

  def active_plan_id
    @active_plan_id ||= user.workout_plans.order(created_at: :desc).limit(1).pick(:id)
  end

  # "19h" or "19h30" from the stored preferred_workout_time.
  def formatted_time
    time = user.health_profile&.preferred_workout_time
    return nil if time.blank?

    minute = time.min
    minute.zero? ? "#{time.hour}h" : format("%dh%02d", time.hour, minute)
  end
end
