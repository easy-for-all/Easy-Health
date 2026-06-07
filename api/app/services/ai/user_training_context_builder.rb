module Ai
  class UserTrainingContextBuilder
    RECENT_SESSIONS_LIMIT = 10

    def initialize(user)
      @user = user
    end

    def call
      {
        current_datetime: Time.current.iso8601,
        current_date:     Time.current.to_date.to_s,
        current_weekday:  Time.current.strftime("%A"),
        user:             user_payload,
        active_plan:      active_plan_payload,
        today_workout:    today_workout_payload,
        last_session:     last_session_payload,
        recent_sessions:  recent_sessions_payload,
        evolution:        evolution_payload
      }
    end

    private

    def user_payload
      hp = @user.health_profile
      {
        id:               @user.id,
        name:             @user.name,
        goal:             hp&.goal,
        experience_level: hp&.fitness_level,
        training_days:    hp&.training_days_per_week,
        modality:         hp&.modality
      }
    end

    def active_plan
      @active_plan ||= @user.workout_plans.where(active: true).order(created_at: :desc).first
    end

    def active_plan_payload
      return nil unless active_plan

      { id: active_plan.id, days_count: active_plan.workout_days.count }
    end

    def today_workout_payload
      return nil unless active_plan

      today_wday = Time.current.wday
      day = active_plan.workout_days.find { |d| d.day_of_week == today_wday }
      day ||= active_plan.workout_days.order(:position).first
      return nil unless day

      exercises = day.workout_day_exercises
                     .includes(:exercise)
                     .order(:order_index)
                     .map do |item|
        {
          name:         item.exercise&.name,
          muscle_group: item.exercise&.muscle_group,
          sets:         item.sets,
          reps:         item.reps,
          rest_seconds: item.rest_seconds
        }
      end

      {
        id:         day.id,
        name:       day.name,
        day_of_week: day.day_of_week,
        exercises:  exercises
      }
    end

    def last_session
      @last_session ||= @user.workout_sessions
                              .order(completed_at: :desc)
                              .first
    end

    def last_session_payload
      return nil unless last_session

      {
        completed_at:     last_session.completed_at,
        duration_minutes: last_session.duration_minutes,
        fatigue_level:    last_session.fatigue_level,
        exercises:        session_exercises(last_session)
      }
    end

    def recent_sessions_payload
      @user.workout_sessions
           .order(completed_at: :desc)
           .limit(RECENT_SESSIONS_LIMIT)
           .map do |s|
        {
          completed_at:     s.completed_at,
          duration_minutes: s.duration_minutes,
          exercises_count:  (s.exercise_logs || []).size,
          total_volume_kg:  total_volume(s)
        }
      end
    end

    def evolution_payload
      sessions = @user.workout_sessions
                       .where("completed_at >= ?", 30.days.ago)
                       .order(completed_at: :desc)

      {
        last_7_days:  sessions.where("completed_at >= ?", 7.days.ago).count,
        last_30_days: sessions.count,
        total_volume_30d: sessions.sum { |s| total_volume(s) }.round(1)
      }
    end

    def session_exercises(session)
      (session.exercise_logs || []).map do |log|
        weights = Array(log["weight_by_set"] || [log["weight_kg"]].compact).map(&:to_f)
        {
          name:       log["name"],
          sets:       log["sets"],
          reps:       Array(log["reps"]),
          weight_kg:  weights,
          volume_kg:  weights.sum * Array(log["reps"]).map(&:to_f).sum
        }
      end
    end

    def total_volume(session)
      session_exercises(session).sum { |e| e[:volume_kg].to_f }
    end
  end
end
