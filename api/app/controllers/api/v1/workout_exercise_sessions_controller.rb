module Api
  module V1
    class WorkoutExerciseSessionsController < BaseController
      before_action :require_active_access!

      # Called when the user starts a new exercise within an in-progress
      # workout session - the "exercise_session" is the execution record,
      # distinct from the WorkoutDayExercise plan it may be based on.
      def create
        workout_session = current_user.workout_sessions.find_by(id: params[:workout_session_id])
        return render json: { error: "Not found" }, status: :not_found unless workout_session

        exercise = Exercise.find_by(id: params[:exercise_id])
        return render json: { errors: [ "exercise not found" ] }, status: :unprocessable_entity unless exercise

        wde = params[:workout_day_exercise_id].present? ? WorkoutDayExercise.find_by(id: params[:workout_day_exercise_id]) : nil
        kind = exercise_kind_for(wde)

        exercise_session = workout_session.exercise_sessions.create!(
          workout_day_exercise: wde,
          exercise: exercise,
          order_index: params[:order_index] || workout_session.exercise_sessions.count,
          exercise_kind: kind,
          planned_sets: params[:planned_sets] || wde&.sets,
          planned_reps: params[:planned_reps] || wde&.reps,
          planned_weight_kg: params[:planned_weight_kg] || wde&.planned_weight,
          rest_seconds: params[:rest_seconds] || wde&.rest_seconds,
          started_at: Time.current
        )

        render json: { id: exercise_session.id, status: exercise_session.status }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      # Marks an exercise as completed/skipped and records its cardio/timed
      # summary fields (sets are recorded separately via WorkoutExerciseSets).
      def update
        exercise_session = ExerciseSession
          .joins(:workout_session)
          .where(workout_sessions: { id: params[:workout_session_id], user_id: current_user.id })
          .find_by(id: params[:id])
        return render json: { error: "Not found" }, status: :not_found unless exercise_session

        attributes = update_params.to_h
        attributes["completed_at"] = Time.current if attributes["status"] == "completed"

        if exercise_session.update(attributes)
          render json: { id: exercise_session.id, status: exercise_session.status }
        else
          render json: { errors: exercise_session.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def exercise_kind_for(wde)
        return "cardio" if wde&.cardio?
        return "timed" if wde&.timed?

        "strength"
      end

      def update_params
        params.permit(
          :status, :feeling, :duration_minutes, :intensity, :elapsed_seconds,
          :target_seconds, :distance_km, :avg_speed_kmh, :avg_pace_per_km
        )
      end
    end
  end
end
