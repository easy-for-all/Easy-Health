module Ai
  class UserTrainingContextBuilder
    RECENT_SESSIONS_LIMIT = 10

    def initialize(user)
      @user = user
    end

    def call
      {
        current_datetime:  Time.current.iso8601,
        current_date:      Time.current.to_date.to_s,
        current_weekday:   Time.current.strftime("%A"),
        user:              user_payload,
        active_plan:       active_plan_payload,
        today_workout:     today_workout_payload,
        last_session:      last_session_payload,
        recent_sessions:   recent_sessions_payload,
        evolution:         evolution_payload,
        dominant_modality: dominant_modality,
        modality_metrics:  modality_metrics_payload
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

    def dominant_modality
      @dominant_modality ||= begin
        sessions = @user.workout_sessions.order(completed_at: :desc).limit(10)
        type_counts = Hash.new(0)
        sessions.each do |s|
          (s.exercise_logs || []).each { |l| type_counts[l["exercise_type"] || "musculacao"] += 1 }
        end
        return "musculacao" if type_counts.empty?

        raw = type_counts.max_by { |_, v| v }&.first
        case raw
        when "cardio", "corrida" then "corrida"
        when "bike"              then "bike"
        when "caminhada"         then "caminhada"
        when "hiit"              then "hiit"
        when "timed"             then "timed"
        when "funcional"         then "funcional"
        else "musculacao"
        end
      end
    end

    def modality_metrics_payload
      sessions = @user.workout_sessions
                      .where("completed_at >= ?", 30.days.ago)
                      .order(completed_at: :desc)
      logs = sessions.flat_map { |s| s.exercise_logs || [] }

      case dominant_modality
      when "corrida", "bike", "caminhada"
        durations = logs.filter_map { |l| l["duration_minutes"].to_f if l["duration_minutes"].to_f > 0 }
        distances = logs.filter_map { |l| l["distance_km"].to_f if l["distance_km"].to_f > 0 }
        {
          total_duration_minutes: durations.sum.round,
          total_distance_km: distances.sum.round(1),
          sessions_count: sessions.count
        }
      when "timed"
        elapsed = logs.filter_map { |l| l["elapsed_seconds"].to_i if l["elapsed_seconds"].to_i > 0 }
        {
          max_hold_seconds: elapsed.max || 0,
          avg_hold_seconds: elapsed.any? ? (elapsed.sum / elapsed.size.to_f).round : 0,
          sessions_count: sessions.count
        }
      when "hiit"
        durations = logs.filter_map { |l| l["duration_minutes"].to_f if l["duration_minutes"].to_f > 0 }
        {
          total_duration_minutes: durations.sum.round,
          sessions_count: sessions.count
        }
      else
        {
          total_volume_kg: sessions.sum { |s| total_volume(s) }.round(1),
          sessions_count: sessions.count
        }
      end
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
