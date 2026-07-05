module Api
  module V1
    class WorkoutExerciseSetsController < BaseController
      before_action :require_active_access!

      # Records one completed set immediately, instead of waiting for the
      # whole workout to finish. Idempotent by (exercise_session, set_number)
      # so a client retry after a dropped connection just updates the same
      # row rather than creating a duplicate.
      def create
        exercise_session = ExerciseSession
          .joins(:workout_session)
          .where(workout_sessions: { id: params[:workout_session_id], user_id: current_user.id })
          .find_by(id: params[:exercise_session_id])
        return render json: { error: "Not found" }, status: :not_found unless exercise_session

        set = exercise_session.exercise_sets.find_or_initialize_by(set_number: params[:set_number])
        set.weight_kg = params[:weight_kg]
        set.reps = params[:reps]
        set.is_warmup = ActiveModel::Type::Boolean.new.cast(params[:is_warmup])
        set.completed_at = Time.current

        if set.save
          render json: { id: set.id, set_number: set.set_number }, status: :created
        else
          render json: { errors: set.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end
end
