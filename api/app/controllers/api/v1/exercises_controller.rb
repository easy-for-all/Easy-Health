module Api
  module V1
    class ExercisesController < BaseController
      def index
        exercises = Exercise.all
        exercises = exercises.where(muscle_group: params[:muscle_group]) if params[:muscle_group].present?
        exercises = exercises.where(exercise_type: params[:exercise_type]) if params[:exercise_type].present?
        exercises = exercises.where.not(id: params[:exclude_ids].to_s.split(",")) if params[:exclude_ids].present?

        render json: exercises.map { |e| exercise_json(e) }
      end

      private

      def exercise_json(exercise)
        {
          id: exercise.id,
          name: exercise.name,
          muscle_group: exercise.muscle_group,
          exercise_type: exercise.exercise_type,
          description: exercise.description,
          image_url: exercise_image_url(exercise),
          muscle_image_url: muscle_image_url(exercise.muscle_group)
        }
      end

      def exercise_image_url(exercise)
        exercise_gif_urls.fetch(exercise.name, exercise_gif_urls.fetch(exercise.exercise_type, "/exercise-images/treino.svg"))
      end

      def muscle_image_url(muscle_group)
        "/muscle-images/#{muscle_group || 'cardio'}.svg"
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
