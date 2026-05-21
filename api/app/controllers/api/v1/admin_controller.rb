module Api
  module V1
    class AdminController < BaseController
      before_action :require_admin!

      def stats
        render json: {
          total_users:               User.count,
          users_with_active_plan:    User.joins(:subscription).where(subscriptions: { status: %w[active trialing] }).count,
          users_in_trial:            User.joins(:subscription).where(subscriptions: { status: "trialing" }).count,
          users_created_workouts:    User.joins(:workout_plans).distinct.count,
          users_completed_workouts:  User.joins(:workout_sessions).distinct.count,
          total_workout_plans:       WorkoutPlan.count,
          total_workout_sessions:    WorkoutSession.count,
          total_uploads:             UserMedia.count
        }
      end
    end
  end
end
