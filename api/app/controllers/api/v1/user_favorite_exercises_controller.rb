module Api
  module V1
    class UserFavoriteExercisesController < BaseController
      def create
        exercise = Exercise.find(params[:id])
        current_user.user_favorite_exercises.find_or_create_by!(exercise: exercise)
        render json: { favorited: true }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Exercise not found" }, status: :not_found
      end

      def destroy
        fav = current_user.user_favorite_exercises.find_by(exercise_id: params[:id])
        fav&.destroy
        render json: { favorited: false }
      end

      def index
        ids = current_user.user_favorite_exercises.pluck(:exercise_id)
        render json: { favorite_exercise_ids: ids }
      end
    end
  end
end
