module AiWorkout
  class DailyLimitChecker
    DEFAULT_PAID_LIMIT = 10
    DEFAULT_FREE_LIMIT = 3

    # Aceita um User (chamada de sempre) ou um Workouts::*Owner. O teto passa a
    # valer também para a instalação anônima, que é onde a geração acontece sem
    # nenhuma conta para responsabilizar.
    def initialize(subject)
      @owner = subject.is_a?(User) ? Workouts::UserOwner.new(subject) : subject
    end

    def limit_reached?
      count = AiTrainingDecisionLog
        .where(owner_filter)
        .where(generation_type: "workout_plan")
        .where(created_at: Time.current.all_day)
        .where(status: "success")
        .count

      count >= daily_limit
    end

    def daily_limit
      if @owner.paid_access?
        ENV.fetch("AI_WORKOUT_DAILY_LIMIT_PAID", DEFAULT_PAID_LIMIT).to_i
      else
        ENV.fetch("AI_WORKOUT_DAILY_LIMIT_FREE", DEFAULT_FREE_LIMIT).to_i
      end
    end

    private

    # Um dono, um filtro. Contar por user_id com user_id nil casaria com TODAS
    # as gerações anônimas do sistema e bloquearia o app inteiro na primeira.
    def owner_filter
      @owner.log_attributes
    end
  end
end
