module Api
  module V1
    class UserFavoriteExercisesController < BaseController
      include ExerciseImageHelper

      def create
        exercise = Exercise.find(params[:id])
        current_user.user_favorite_exercises.find_or_create_by!(exercise: exercise)
        FitnessIntelligence.recalculate_safely(user: current_user, source: "favorite_exercise_added")
        render json: { favorited: true }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Exercise not found" }, status: :not_found
      end

      def destroy
        fav = current_user.user_favorite_exercises.find_by(exercise_id: params[:id])
        fav&.destroy
        FitnessIntelligence.recalculate_safely(user: current_user, source: "favorite_exercise_removed")
        render json: { favorited: false }
      end

      def index
        favorites = current_user.user_favorite_exercises.includes(:exercise)
        render json: favorites.map { |fav|
          ex = fav.exercise
          { id: ex.id, name: ex.name, muscle_group: ex.muscle_group, image_url: exercise_image_url(ex) }
        }
      end
    end
  end
end
