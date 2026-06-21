module AiWorkout
  class DailyLimitChecker
    DEFAULT_PAID_LIMIT = 10
    DEFAULT_FREE_LIMIT = 3

    def initialize(user)
      @user = user
    end

    def limit_reached?
      count = AiTrainingDecisionLog
        .where(user_id: @user.id, generation_type: "workout_plan")
        .where(created_at: Time.current.all_day)
        .where(status: "success")
        .count

      count >= daily_limit
    end

    def daily_limit
      if @user.premium_active? || @user.trial_active?
        ENV.fetch("AI_WORKOUT_DAILY_LIMIT_PAID", DEFAULT_PAID_LIMIT).to_i
      else
        ENV.fetch("AI_WORKOUT_DAILY_LIMIT_FREE", DEFAULT_FREE_LIMIT).to_i
      end
    end
  end
end
