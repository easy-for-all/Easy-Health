module Api
  module V1
    class WorkoutDaysController < BaseController
      def toggle_favorite
        day = WorkoutDay
          .joins(workout_plan: :user)
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:id])

        day.update!(favorited: !day.favorited)
        render json: { favorited: day.favorited }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Workout day not found" }, status: :not_found
      end
    end
  end
end
