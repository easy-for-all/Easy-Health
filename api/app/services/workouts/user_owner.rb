module Workouts
  # O dono de sempre. Cada método delega para o User exatamente como o código
  # fazia antes da extração — é isto que garante que o caminho autenticado não
  # mudou de comportamento ao ganhar a abstração.
  class UserOwner
    attr_reader :user

    def initialize(user)
      @user = user
    end

    def installation = nil
    def anonymous? = false
    def plans = WorkoutPlan.where(user_id: @user.id)
    def sessions = WorkoutSession.where(user_id: @user.id)
    def plan_attributes = { user_id: @user.id }
    def log_attributes = { user_id: @user.id }

    def health_profile
      @user.health_profile
    end

    def favorite_exercise_ids(exercise_ids)
      return Set.new if exercise_ids.empty?

      @user.user_favorite_exercises.where(exercise_id: exercise_ids).pluck(:exercise_id).to_set
    end

    def all_favorite_exercise_ids
      @user.user_favorite_exercises.pluck(:exercise_id)
    end

    def active_plan
      @user.active_workout_plan
    end

    # Trial e assinatura são coisas de conta; o limite diário de IA usa isto
    # para escolher entre o teto pago e o gratuito.
    def paid_access?
      @user.premium_active? || @user.trial_active?
    end

    def history_for(exercise_id:, block_type:)
      ExerciseHistoryService.new(user: @user, exercise_id: exercise_id, block_type: block_type)
    end
  end
end
