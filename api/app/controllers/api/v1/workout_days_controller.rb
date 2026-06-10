module Api
  module V1
    class WorkoutDaysController < BaseController
      def toggle_favorite
        day = find_user_day
        day.update!(favorited: !day.favorited)
        render json: { favorited: day.favorited }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Workout day not found" }, status: :not_found
      end

      def rename
        day = find_user_day
        custom_name = params[:custom_name].to_s.strip
        day.update!(custom_name: custom_name.presence)
        render json: { id: day.id, custom_name: day.custom_name }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Workout day not found" }, status: :not_found
      end

      private

      def find_user_day
        WorkoutDay
          .joins(workout_plan: :user)
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:id])
      end
    end
  end
end
