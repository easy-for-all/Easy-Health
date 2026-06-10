module Api
  module V1
    class WorkoutPlansController < BaseController
      before_action(only: [:regenerate]) { check_rate_limit!(:generate_workout) }

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
        modality             = params[:modality].presence
        split_type           = params[:split_type].presence
        cardio_type          = params[:cardio_type].presence
        cardio_format        = params[:cardio_format].presence
        custom_splits        = params[:custom_splits].presence
        training_location    = params[:training_location].presence

        if days_per_week && !days_per_week.between?(2, 6)
          return render_error("training_days_per_week must be between 2 and 6")
        end

        profile_attrs = {}
        profile_attrs[:training_days_per_week] = days_per_week        if days_per_week
        profile_attrs[:activity_preferences]   = activity_preferences if activity_preferences
        profile_attrs[:modality]               = modality             if modality
        profile_attrs[:split_type]             = split_type           if split_type
        profile_attrs[:cardio_type]            = cardio_type          if cardio_type
        profile_attrs[:cardio_format]          = cardio_format        if cardio_format
        profile_attrs[:custom_splits]          = custom_splits        if custom_splits
        profile_attrs[:training_location]      = training_location    if training_location
        current_user.health_profile&.update!(profile_attrs) if profile_attrs.any?

        service = WorkoutPlanGeneratorService.new(
          current_user,
          days_per_week:        days_per_week,
          activity_preferences: activity_preferences,
          modality:             modality,
          split_type:           split_type,
          cardio_type:          cardio_type,
          cardio_format:        cardio_format,
          custom_splits:        custom_splits,
          training_location:    training_location
        )
        plan = service.call
        render json: serialize_plan(plan).merge(summary: service.plan_summary), status: :ok
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

      def duplicate_day
        source = WorkoutDay
          .joins(workout_plan: :user)
          .where(workout_plans: { user_id: current_user.id })
          .find(params[:id])

        plan = source.workout_plan
        max_position = plan.workout_days.maximum(:position) || plan.workout_days.count
        new_day = plan.workout_days.create!(
          name: "#{source.name} (cópia)",
          day_of_week: nil,
          position: max_position + 1
        )

        source.workout_day_exercises.includes(:exercise).each_with_index do |wde, idx|
          new_day.workout_day_exercises.create!(
            exercise: wde.exercise,
            sets: wde.sets,
            reps: wde.reps,
            rest_seconds: wde.rest_seconds,
            duration_minutes: wde.duration_minutes,
            intensity: wde.intensity,
            order_index: idx
          )
        end

        render json: { day: serialize_day_with_exercises(new_day) }, status: :created
      rescue ActiveRecord::RecordNotFound
        render json: { error: "Not found" }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      end

      private

      def serialize_plan_summary(plan)
        days = plan.workout_days.includes(workout_day_exercises: :exercise).order(Arel.sql("COALESCE(position, day_of_week) ASC"))
        {
          id: plan.id,
          active: plan.active,
          created_at: plan.created_at,
          days_count: days.count,
          days: days.map { |d| { id: d.id, name: d.name, custom_name: d.custom_name, exercise_count: d.workout_day_exercises.count } }
        }
      end

      def serialize_plan(plan)
        log = plan.ai_training_decision_log
        days = plan.workout_days.order(Arel.sql("COALESCE(position, day_of_week) ASC")).to_a
        last_completed = last_completed_at_by_day(days.map(&:id))
        {
          id: plan.id,
          active: plan.active,
          ai_rationale:       log&.rationale,
          ai_training_method: log&.training_method,
          days: days.map { |d| serialize_day(d, last_completed[d.id]) }
        }
      end

      def serialize_day(day, last_completed_at = nil)
        exercises = day.workout_day_exercises.includes(:exercise)
        {
          id: day.id,
          position: day.position,
          day_of_week: day.day_of_week,
          name: day.name,
          custom_name: day.custom_name,
          favorited: day.favorited,
          muscle_groups: exercises.map { |wde| wde.exercise.muscle_group }.compact.uniq,
          exercise_types: exercises.map { |wde| wde.exercise.exercise_type }.compact.uniq,
          exercise_count: exercises.count,
          last_completed_at: last_completed_at
        }
      end

      def serialize_day_with_exercises(day)
        wdes = day.workout_day_exercises.includes(:exercise).to_a
        exercise_ids   = wdes.map { |wde| wde.exercise.id }
        last_performed = exercise_last_performed(current_user, exercise_ids)
        favorite_ids   = current_user.user_favorite_exercises
                                     .where(exercise_id: exercise_ids)
                                     .pluck(:exercise_id).to_set

        {
          id: day.id,
          position: day.position,
          day_of_week: day.day_of_week,
          name: day.name,
          custom_name: day.custom_name,
          favorited: day.favorited,
          last_completed_at: last_completed_at_by_day([day.id])[day.id],
          exercises: wdes.map do |wde|
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
              video_url: wde.exercise.video_url,
              muscle_image_url: muscle_image_url(wde.exercise.muscle_group),
              sets: wde.sets,
              reps: wde.reps,
              rest_seconds: wde.rest_seconds,
              duration_minutes: wde.duration_minutes,
              intensity: wde.intensity,
              order_index: wde.order_index,
              is_favorite: favorite_ids.include?(wde.exercise.id),
              last_performed_at: last_performed[wde.exercise.id]
            }
          end
        }
      end

      # Returns hash { exercise_id => completed_at } for the user's most recent session per exercise
      def exercise_last_performed(user, exercise_ids)
        return {} if exercise_ids.empty?

        rows = ActiveRecord::Base.connection.execute(<<~SQL.squish)
          SELECT DISTINCT ON ((elem->>'exercise_id')::integer)
            (elem->>'exercise_id')::integer AS exercise_id,
            completed_at
          FROM workout_sessions,
            jsonb_array_elements(exercise_logs) AS elem
          WHERE user_id = #{user.id.to_i}
            AND (elem->>'exercise_id')::integer = ANY(ARRAY[#{exercise_ids.map(&:to_i).join(',')}])
          ORDER BY (elem->>'exercise_id')::integer, completed_at DESC
        SQL

        rows.each_with_object({}) do |row, hash|
          hash[row["exercise_id"].to_i] = row["completed_at"]
        end
      end

      # Returns hash { workout_day_id => completed_at } — last session per day for current user
      def last_completed_at_by_day(day_ids)
        return {} if day_ids.empty?

        WorkoutSession
          .where(user_id: current_user.id, workout_day_id: day_ids)
          .select("DISTINCT ON (workout_day_id) workout_day_id, completed_at")
          .order("workout_day_id, completed_at DESC")
          .each_with_object({}) { |s, h| h[s.workout_day_id] = s.completed_at }
      end

      include ExerciseImageHelper
    end
  end
end
