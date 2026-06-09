module Api
  module V1
    class WorkoutSessionsController < BaseController
      PER_PAGE = 20

      def index
        page = [params[:page].to_i, 1].max
        sessions = current_user.workout_sessions
          .includes(:workout_day)
          .order(completed_at: :desc)
        sessions = sessions.where("completed_at >= ?", 7.days.ago) if params[:recent].present?
        total = sessions.count
        sessions = sessions
          .limit(PER_PAGE)
          .offset((page - 1) * PER_PAGE)

        render json: {
          sessions: sessions.map { |s| session_json(s) },
          total: total
        }
      end

      def create
        unless current_user.can_access_workout?
          render json: { error: "Plano ativo necessário." }, status: :forbidden and return
        end

        session = current_user.workout_sessions.build(session_params)
        session.completed_at ||= Time.current

        workout_day = WorkoutDay.includes(workout_day_exercises: :exercise).find_by(id: session.workout_day_id)
        calories = CalorieEstimationService.new(
          duration_minutes: session.duration_minutes,
          workout_day: workout_day,
          user: current_user
        ).estimate
        session.calories_estimated = calories if calories > 0

        if session.save
          mark_free_workout_used if !current_user.admin? && !current_user.paid_plan? && !current_user.free_workout_used?
          render json: session_json(session), status: :created
        else
          render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def stats
        sessions = current_user.workout_sessions.order(completed_at: :desc)
        weekly = sessions.select { |s| s.completed_at >= 7.days.ago }
        goal = current_user.health_profile&.training_days_per_week || 3
        total_volume = calculate_total_volume(sessions)
        streak_svc = WorkoutStreakService.new(sessions)

        render json: {
          total_sessions: sessions.count,
          streak: streak_svc.current_streak,
          best_streak: streak_svc.best_streak,
          last_activity_at: streak_svc.last_activity_at,
          weekly_sessions: weekly.count,
          weekly_goal: goal,
          total_volume_kg: total_volume
        }
      end

      def today
        session = current_user.workout_sessions
          .includes(:workout_day)
          .where("completed_at >= ?", Time.current.beginning_of_day)
          .order(completed_at: :desc)
          .first
        render json: session ? session_json(session) : {}
      end

      def update
        session = current_user.workout_sessions.find_by(id: params[:id])
        return render json: { error: "Not found" }, status: :not_found unless session

        if session.update(update_params)
          render json: session_json(session)
        else
          render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def personal_records
        sessions = current_user.workout_sessions
          .where("exercise_logs IS NOT NULL")
          .order(completed_at: :desc)

        records = {}
        sessions.each do |session|
          (session.exercise_logs || []).each do |log|
            next unless log["exercise_id"] && log["weight_kg"].to_f > 0
            ex_id = log["exercise_id"]
            weight = log["weight_kg"].to_f
            if records[ex_id].nil? || weight > records[ex_id][:max_weight_kg]
              records[ex_id] = {
                exercise_id: ex_id,
                exercise_name: log["name"],
                max_weight_kg: weight,
                achieved_at: session.completed_at
              }
            end
          end
        end

        render json: records.values
      end

      private

      def mark_free_workout_used
        current_user.update_columns(
          free_workout_used: true,
          first_workout_completed_at: Time.current
        )
      end

      def update_params
        params.permit(:fatigue_level, :notes)
      end

      def session_params
        params.permit(
          :workout_day_id,
          :duration_minutes,
          :notes,
          :completed_at,
          :fatigue_level,
          exercise_logs: [
            :workout_day_exercise_id,
            :exercise_id,
            :name,
            :weight_kg,
            :planned_sets,
            :sets,
            :rest_seconds,
            :feeling,
            :duration_minutes,
            :intensity,
            weight_by_set: [],
            reps: []
          ]
        )
      end

      def session_json(s)
        {
          id: s.id,
          workout_day_id: s.workout_day_id,
          workout_day_name: s.workout_day.name,
          completed_at: s.completed_at,
          duration_minutes: s.duration_minutes,
          fatigue_level: s.fatigue_level,
          exercise_logs: s.exercise_logs || [],
          notes: s.notes,
          calories_estimated: s.calories_estimated
        }
      end

      def calculate_total_volume(sessions)
        total = 0.0
        sessions.each do |session|
          (session.exercise_logs || []).each do |log|
            weight = log["weight_kg"].to_f
            next if weight == 0
            reps_array = Array(log["reps"])
            sets = log["sets"].to_i
            reps_per_set = reps_array.empty? ? log["reps"].to_i : reps_array.sum.to_f / [reps_array.size, 1].max
            total += weight * reps_per_set * sets
          end
        end
        total.round
      end

    end
  end
end
