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

        if current_exercise_ids.include?(replacement.id) || !same_target?(wde.exercise, replacement)
          return render json: { error: "Replacement must be a different exercise for the same muscle group" }, status: :unprocessable_entity
        end

        wde.update!(exercise: replacement)

        render json: workout_day_exercise_json(wde.reload)
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
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
          muscle_image_url: "/muscle-images/#{exercise.muscle_group || 'cardio'}.svg",
          sets: wde.sets,
          reps: wde.reps,
          rest_seconds: wde.rest_seconds,
          order_index: wde.order_index
        }
      end

      def exercise_image_url(exercise)
        exercise_gif_urls.fetch(exercise.name, exercise_gif_urls.fetch(exercise.exercise_type, "/exercise-images/treino.svg"))
      end

      def exercise_gif_urls
        {
          "Push-up" => "https://d205bpvrqc9yn1.cloudfront.net/0662.gif",
          "Bench Press" => "https://d205bpvrqc9yn1.cloudfront.net/0025.gif",
          "Pull-up" => "https://d205bpvrqc9yn1.cloudfront.net/1429.gif",
          "Bent-over Row" => "https://d205bpvrqc9yn1.cloudfront.net/0027.gif",
          "Overhead Press" => "https://d205bpvrqc9yn1.cloudfront.net/0082.gif",
          "Lateral Raise" => "https://d205bpvrqc9yn1.cloudfront.net/0334.gif",
          "Bicep Curl" => "https://d205bpvrqc9yn1.cloudfront.net/0023.gif",
          "Hammer Curl" => "https://d205bpvrqc9yn1.cloudfront.net/0313.gif",
          "Tricep Dip" => "https://d205bpvrqc9yn1.cloudfront.net/0814.gif",
          "Skull Crusher" => "https://d205bpvrqc9yn1.cloudfront.net/0035.gif",
          "Squat" => "https://d205bpvrqc9yn1.cloudfront.net/0043.gif",
          "Lunges" => "https://d205bpvrqc9yn1.cloudfront.net/0054.gif",
          "Deadlift" => "https://d205bpvrqc9yn1.cloudfront.net/0032.gif",
          "Plank" => "https://d205bpvrqc9yn1.cloudfront.net/0463.gif",
          "Crunch" => "https://d205bpvrqc9yn1.cloudfront.net/0003.gif",
          "corrida" => "/exercise-images/corrida.svg",
          "caminhada" => "/exercise-images/caminhada.svg",
          "natacao" => "/exercise-images/natacao.svg",
          "cardio" => "/exercise-images/cardio.svg",
          "hiit" => "/exercise-images/hiit.svg",
          "funcional" => "/exercise-images/funcional.svg",
          "musculacao" => "/exercise-images/treino.svg"
        }
      end
    end
  end
end
