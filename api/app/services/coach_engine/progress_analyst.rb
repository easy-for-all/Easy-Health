module CoachEngine
  class ProgressAnalyst
    METRIC_FIELDS = %w[weight_kg body_fat_pct muscle_mass_kg].freeze
    CONFIRMED_STATUSES = %w[confirmed saved_advanced].freeze
    WINDOW_DAYS = 28

    def initialize(user:, fitness_profile:, health_profile: nil, now: Time.current)
      @user = user
      @fitness_profile = fitness_profile
      @health_profile = health_profile || user.health_profile
      @now = now
    end

    def call
      trends = metric_trends
      session_trend = session_trend_summary
      direction = progress_direction(trends, session_trend)
      {
        "progress_summary" => summary_for(direction, trends, session_trend),
        "progress_direction" => direction,
        "concerns" => concerns_for(trends, session_trend),
        "opportunities" => opportunities_for(direction, session_trend),
        "confidence" => confidence(trends, session_trend),
        "evidence" => {
          "metric_trends" => trends,
          "session_trend" => session_trend
        }
      }
    end

    private

    def metric_trends
      confirmed_points.group_by(&:field_name).each_with_object({}) do |(field, points), trends|
        next unless METRIC_FIELDS.include?(field) && points.size >= 2

        previous, latest = points.sort_by { |point| point.collected_at || point.created_at }.last(2)
        trends[field] = numeric_trend(previous.value, latest.value)
      end
    end

    def session_trend_summary
      current_sessions = sessions_between(@now - WINDOW_DAYS.days, @now)
      previous_sessions = sessions_between(@now - (WINDOW_DAYS * 2).days, @now - WINDOW_DAYS.days)
      {
        "current_sessions" => current_sessions.size,
        "previous_sessions" => previous_sessions.size,
        "frequency_trend" => numeric_trend(previous_sessions.size, current_sessions.size),
        "volume_trend" => numeric_trend(total_volume(previous_sessions), total_volume(current_sessions))
      }
    end

    def progress_direction(trends, session_trend)
      return "mixed" if trends["weight_kg"] == "down" && trends["muscle_mass_kg"] == "down"

      case @health_profile&.goal
      when "lose_weight"
        return "improving" if trends["body_fat_pct"] == "down" || (trends["weight_kg"] == "down" && trends["muscle_mass_kg"] != "down")
      when "gain_muscle"
        return "improving" if trends["muscle_mass_kg"] == "up" || session_trend["volume_trend"] == "up"
      end

      return "improving" if session_trend["frequency_trend"] == "up" && session_trend["volume_trend"] != "down"
      return "stable" if trends.any? || session_trend["current_sessions"].positive? || session_trend["previous_sessions"].positive?

      "insufficient_data"
    end

    def summary_for(direction, trends, session_trend)
      case direction
      when "improving" then "Os dados recentes mostram evolução compatível com o objetivo atual."
      when "mixed" then "Os dados recentes mostram sinais mistos e pedem uma estratégia conservadora."
      when "stable" then "Há dados de treino, mas ainda não existe uma mudança clara de tendência."
      else "Ainda não há dados suficientes para identificar uma tendência de evolução."
      end
    end

    def concerns_for(trends, session_trend)
      concerns = []
      concerns << "muscle_mass_decreasing_with_weight_loss" if trends["weight_kg"] == "down" && trends["muscle_mass_kg"] == "down"
      concerns << "training_frequency_decreasing" if session_trend["frequency_trend"] == "down"
      concerns
    end

    def opportunities_for(direction, session_trend)
      opportunities = []
      opportunities << "maintain_current_progression" if direction == "improving"
      opportunities << "build_training_consistency" if session_trend["current_sessions"] < (@health_profile&.training_days_per_week || 3) * 2
      opportunities << "collect_confirmed_progress_data" if direction == "insufficient_data"
      opportunities.uniq
    end

    def confidence(trends, session_trend)
      value = 0.15
      value += [ trends.size * 0.25, 0.5 ].min
      value += 0.2 if session_trend["current_sessions"].positive? && session_trend["previous_sessions"].positive?
      value.clamp(0, 0.9).round(2)
    end

    def confirmed_points
      @confirmed_points ||= @user.health_data_points.where(status: CONFIRMED_STATUSES, field_name: METRIC_FIELDS).to_a
    end

    def sessions_between(start_time, end_time)
      @user.workout_sessions.where(completed_at: start_time...end_time).to_a
    end

    def total_volume(sessions)
      sessions.sum do |session|
        Array(session.exercise_logs).sum do |log|
          weights = Array(log["weight_by_set"] || [ log["weight_kg"] ].compact).map(&:to_f)
          reps = Array(log["reps"])
          sets = log["sets"].to_i
          reps = Array.new(sets, log["reps"].to_i) if reps.empty? && sets.positive?
          weights.each_with_index.sum { |weight, index| weight * reps.fetch(index, 0).to_f }
        end
      end
    end

    def numeric_trend(previous, latest)
      previous_value = previous.to_f
      latest_value = latest.to_f
      return "stable" if previous_value.zero? && latest_value.zero?
      return "up" if latest_value > previous_value * 1.02
      return "down" if latest_value < previous_value * 0.98

      "stable"
    end
  end
end
