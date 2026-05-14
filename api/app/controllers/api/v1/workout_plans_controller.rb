module Api
  module V1
    class WorkoutPlansController < BaseController
      def index
        plans = current_user.workout_plans.order(created_at: :desc)
        render json: plans.map { |p| serialize_plan_summary(p) }
      end

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

      def serialize_plan_summary(plan)
        days = plan.workout_days.includes(workout_day_exercises: :exercise).order(Arel.sql("COALESCE(position, day_of_week) ASC"))
        {
          id: plan.id,
          active: plan.active,
          created_at: plan.created_at,
          days_count: days.count,
          days: days.map { |d| { id: d.id, name: d.name, exercise_count: d.workout_day_exercises.count } }
        }
      end

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
              instructions: wde.exercise.instructions,
              image_url: exercise_image_url(wde.exercise),
              gif_url: wde.exercise.gif_url,
              muscle_image_url: muscle_image_url(wde.exercise.muscle_group),
              sets: wde.sets,
              reps: wde.reps,
              rest_seconds: wde.rest_seconds,
              order_index: wde.order_index
            }
          end
        }
      end

      include ExerciseImageHelper
    end
  end
end
