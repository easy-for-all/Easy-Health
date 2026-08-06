module Api
  module V1
    class WorkoutPlansController < BaseController
      include WorkoutBlockSerialization
      include WorkoutPlanSerialization

      before_action :require_active_access!, only: [:regenerate]
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
        selected_muscles     = sanitize_selected_muscles(params[:selected_muscles])
        muscle_priorities    = sanitize_muscle_priorities(params[:muscle_priorities])

        if days_per_week && !days_per_week.between?(1, 6)
          return render_error("training_days_per_week must be between 1 and 6")
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
        profile_attrs[:selected_muscle_groups] = selected_muscles     unless selected_muscles.nil?
        profile_attrs[:muscle_priorities]      = muscle_priorities    unless muscle_priorities.nil?
        current_user.health_profile&.update!(profile_attrs) if profile_attrs.any?

        FitnessIntelligence.recalculate_safely(user: current_user, source: "workout_plan_regenerated")
        had_workout_plan = current_user.workout_plans.exists?
        service = WorkoutPlanGeneratorService.new(
          current_user,
          days_per_week:        days_per_week,
          activity_preferences: activity_preferences,
          modality:             modality,
          split_type:           split_type,
          cardio_type:          cardio_type,
          cardio_format:        cardio_format,
          custom_splits:        custom_splits,
          training_location:    training_location,
          selected_muscles:     selected_muscles,
          muscle_priorities:    muscle_priorities
        )
        plan = service.call
        UserEventService.track(
          user: current_user,
          event: :workout_created,
          metadata: { workout_plan_id: plan.id },
          occurred_at: plan.created_at,
          idempotency_key: "workout_created:#{current_user.id}:#{plan.id}"
        )
        unless had_workout_plan
          UserEventService.track(
            user: current_user,
            event: :first_workout_created,
            metadata: { workout_plan_id: plan.id },
            occurred_at: plan.created_at,
            idempotency_key: "first_workout_created:#{current_user.id}:#{plan.id}"
          )
          track_activation_workout_created(plan)
        end
        render json: serialize_plan(plan).merge(summary: service.plan_summary), status: :ok
      rescue ActiveRecord::RecordInvalid => e
        render_error(e.record.errors.full_messages.to_sentence)
      rescue StandardError => e
        Rails.logger.error("[WorkoutPlansController#regenerate] #{e.class}: #{e.message}")
        render json: { error: "Não foi possível gerar o plano. Tente novamente." }, status: :internal_server_error
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

      # Só aceita ids dentro de Exercise::MUSCLE_GROUPS. `nil` = param ausente
      # (não mexe no profile); `[]` = seleção explicitamente limpa.
      def sanitize_selected_muscles(raw)
        return nil if raw.nil?

        Array(raw).map(&:to_s) & Exercise::MUSCLE_GROUPS
      end

      # { "chest" => "high", ... } restrito a grupos e níveis válidos.
      def sanitize_muscle_priorities(raw)
        return nil if raw.blank?

        allowed = %w[high normal avoid]
        raw.to_unsafe_h.each_with_object({}) do |(group, priority), acc|
          group = group.to_s
          priority = priority.to_s
          acc[group] = priority if Exercise::MUSCLE_GROUPS.include?(group) && allowed.include?(priority)
        end
      end

      def track_activation_workout_created(plan)
        days = plan.workout_days.includes(workout_day_exercises: :exercise)
                   .order(Arel.sql("COALESCE(position, day_of_week) ASC")).to_a
        first_day = days.first
        exercises_count = days.sum { |d| d.workout_day_exercises.size }
        muscle_groups = days.flat_map { |d| d.workout_day_exercises.map { |wde| wde.exercise.muscle_group } }.compact.uniq

        UserEventService.track(
          user: current_user,
          event: :activation_workout_created,
          metadata: {
            workout_plan_id: plan.id,
            trigger_type: "activation_workout_created",
            workout: {
              id: plan.id,
              name: first_day&.custom_name.presence || first_day&.name,
              exercises_count: exercises_count,
              estimated_duration_minutes: current_user.health_profile&.session_duration_minutes,
              muscle_groups: muscle_groups
            },
            activation: {
              onboarding_variant: current_user.onboarding_flow,
              has_started_workout: false,
              has_completed_first_workout: false
            }
          },
          occurred_at: plan.created_at,
          idempotency_key: "activation_workout_created:#{current_user.id}:#{plan.id}"
        )
      end

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

      # Este controller é sempre autenticado, então o dono da serialização é
      # sempre o usuário da sessão. O serializer em si vive em
      # WorkoutPlanSerialization, compartilhado com o endpoint anônimo.
      def plan_owner
        @plan_owner ||= Workouts::UserOwner.new(current_user)
      end

    end
  end
end
