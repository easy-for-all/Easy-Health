module Api
  module V1
    class WorkoutPlansController < BaseController
      def show
        plan = current_user.active_workout_plan
        return render json: { error: "No active plan found" }, status: :not_found unless plan

        render json: serialize_plan(plan)
      end

      def regenerate
        days_per_week        = params[:training_days_per_week]&.to_i
        activity_preferences = Array(params[:activity_preferences]).presence

        if days_per_week && !days_per_week.between?(2, 6)
          return render_error("training_days_per_week must be between 2 and 6")
        end

        profile_attrs = {}
        profile_attrs[:training_days_per_week] = days_per_week if days_per_week
        profile_attrs[:activity_preferences]   = activity_preferences if activity_preferences
        current_user.health_profile&.update!(profile_attrs) if profile_attrs.any?

        plan = WorkoutPlanGeneratorService.new(
          current_user,
          days_per_week:        days_per_week,
          activity_preferences: activity_preferences
        ).call
        render json: serialize_plan(plan), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render_error(e.record.errors.full_messages.to_sentence)
      end

      def today
        plan = current_user.active_workout_plan
        return render json: { error: "No active plan found" }, status: :not_found unless plan

        today_dow = Date.today.wday
        day = plan.workout_days.find_by(day_of_week: today_dow)
        return render json: { day: nil, message: "Rest day" } unless day

        render json: { day: serialize_day_with_exercises(day) }
      end

      def day
        day = WorkoutDay
          .joins(workout_plan: :user)
          .where(workout_plans: { user_id: current_user.id, active: true })
          .find(params[:id])

        render json: { day: serialize_day_with_exercises(day) }
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Workout not found" }, status: :not_found
      end

      private

      def serialize_plan(plan)
        {
          id: plan.id,
          active: plan.active,
          days: plan.workout_days.order(Arel.sql("COALESCE(position, day_of_week) ASC")).map { |d| serialize_day(d) }
        }
      end

      def serialize_day(day)
        exercises = day.workout_day_exercises.includes(:exercise)
        {
          id: day.id,
          position: day.position,
          day_of_week: day.day_of_week,
          name: day.name,
          muscle_groups: exercises.map { |wde| wde.exercise.muscle_group }.compact.uniq,
          exercise_types: exercises.map { |wde| wde.exercise.exercise_type }.compact.uniq,
          exercise_count: exercises.count
        }
      end

      def serialize_day_with_exercises(day)
        {
          id: day.id,
          position: day.position,
          day_of_week: day.day_of_week,
          name: day.name,
          exercises: day.workout_day_exercises.includes(:exercise).map do |wde|
            {
              workout_day_exercise_id: wde.id,
              exercise_id: wde.exercise.id,
              name: wde.exercise.name,
              muscle_group: wde.exercise.muscle_group,
              exercise_type: wde.exercise.exercise_type,
              description: wde.exercise.description,
              image_url: exercise_image_url(wde.exercise),
              muscle_image_url: muscle_image_url(wde.exercise.muscle_group),
              sets: wde.sets,
              reps: wde.reps,
              rest_seconds: wde.rest_seconds,
              order_index: wde.order_index
            }
          end
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
