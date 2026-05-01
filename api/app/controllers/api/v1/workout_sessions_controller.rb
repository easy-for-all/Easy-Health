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
        session = current_user.workout_sessions.build(session_params)
        session.completed_at ||= Time.current

        if session.save
          render json: session_json(session), status: :created
        else
          render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def stats
        sessions = current_user.workout_sessions.order(completed_at: :desc)
        render json: { total_sessions: sessions.count, streak: calculate_streak(sessions) }
      end

      private

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
          notes: s.notes
        }
      end

      def calculate_streak(sessions)
        return 0 if sessions.empty?

        dates = sessions.map { |s| s.completed_at.to_date }.uniq.sort.reverse
        streak = 0
        expected = Date.today

        dates.each do |date|
          break if date < expected - 1

          streak += 1
          expected = date - 1
        end

        streak
      end
    end
  end
end
