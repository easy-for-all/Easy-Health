module Api
  module V1
    class WorkoutDayExercisesController < BaseController
      def swap
        wde = WorkoutDayExercise
          .joins(workout_day: { workout_plan: :user })
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:id])

        replacement = Exercise.find(params[:replacement_exercise_id])
        current_exercise_ids = wde.workout_day.workout_day_exercises.where.not(id: wde.id).pluck(:exercise_id)

        if current_exercise_ids.include?(replacement.id)
          return render json: { error: "Exercise is already in this workout day" }, status: :unprocessable_entity
        end

        unless same_target?(wde.exercise, replacement)
          return render json: { error: "Replacement must target the same muscle group as the original exercise" }, status: :unprocessable_entity
        end

        wde.update!(exercise: replacement)

        render json: workout_day_exercise_json(wde.reload)
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def update
        wde = WorkoutDayExercise
          .joins(workout_day: { workout_plan: :user })
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:id])

        wde.update!(update_params)
        render json: workout_day_exercise_json(wde.reload)
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def destroy
        wde = WorkoutDayExercise
          .joins(workout_day: { workout_plan: :user })
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:id])

        if wde.workout_day.workout_day_exercises.count <= 1
          return render json: { error: "Cannot remove the last exercise from a workout day" }, status: :unprocessable_entity
        end

        wde.destroy!
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      def create
        day = WorkoutDay
          .joins(workout_plan: :user)
          .where(workout_plans: { user_id: current_user.id, active: true })
          .find(params[:workout_day_id])

        exercise = Exercise.find(params[:exercise_id])
        current_exercise_ids = day.workout_day_exercises.pluck(:exercise_id)

        if current_exercise_ids.include?(exercise.id)
          return render json: { error: "Exercise is already in this workout" }, status: :unprocessable_entity
        end

        reference = day.workout_day_exercises.includes(:exercise).find { |wde| same_target?(wde.exercise, exercise) }
        unless reference
          return render json: { error: "Exercise must match a muscle group already trained here" }, status: :unprocessable_entity
        end

        wde = day.workout_day_exercises.create!(
          exercise: exercise,
          sets: reference.sets,
          reps: reference.reps,
          rest_seconds: reference.rest_seconds,
          order_index: (day.workout_day_exercises.maximum(:order_index) || -1) + 1
        )

        render json: workout_day_exercise_json(wde), status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      end

      private

      def update_params
        params.permit(:sets, :reps, :rest_seconds)
      end

      def same_target?(current, replacement)
        current.muscle_group.present? ? current.muscle_group == replacement.muscle_group : current.exercise_type == replacement.exercise_type
      end

      def workout_day_exercise_json(wde)
        exercise = wde.exercise
        {
          workout_day_exercise_id: wde.id,
          exercise_id: exercise.id,
          name: exercise.name,
          muscle_group: exercise.muscle_group,
          exercise_type: exercise.exercise_type,
          description: exercise.description,
          image_url: exercise_image_url(exercise),
          muscle_image_url: muscle_image_url(exercise.muscle_group),
          sets: wde.sets,
          reps: wde.reps,
          rest_seconds: wde.rest_seconds,
          order_index: wde.order_index
        }
      end

      include ExerciseImageHelper
    end
  end
end
