module Api
  module V1
    class WorkoutSessionsController < BaseController
      PER_PAGE = 20

      before_action :require_active_access!, only: [:create, :stats, :personal_records, :monthly_summary]

      def index
        page = [params[:page].to_i, 1].max
        sessions = current_user.workout_sessions
          .includes(:workout_day)
          .order(completed_at: :desc)
        sessions = sessions.where("completed_at >= ?", 7.days.ago) if params[:recent].present?
        sessions = sessions.where(completed_at: params[:from]..) if params[:from].present?
        sessions = sessions.where(completed_at: ..params[:to])   if params[:to].present?
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
        Rails.logger.info("[WorkoutSessionCreate] user=#{current_user.id} workout_day_id=#{params[:workout_day_id].inspect} source=#{params[:source].inspect} duration=#{params[:duration_minutes].inspect}")

        session = current_user.workout_sessions.build(session_params)
        session.completed_at ||= Time.current

        workout_day = nil
        if session.workout_day_id.present?
          workout_day = WorkoutDay.includes(workout_day_exercises: :exercise).find_by(id: session.workout_day_id)
          session.workout_day_id = nil unless workout_day
        end

        calories = CalorieEstimationService.new(
          duration_minutes: session.duration_minutes,
          workout_day: workout_day,
          user: current_user
        ).estimate
        session.calories_estimated = calories if calories > 0

        if session.save
          mark_free_workout_used if !current_user.admin? && !current_user.paid_plan? && !current_user.free_workout_used?
          UserEventService.track(user: current_user, event: :workout_completed, metadata: { session_id: session.id, duration_minutes: session.duration_minutes })
          FitnessIntelligence.recalculate_safely(user: current_user, source: "workout_completed")
          render json: session_json(session), status: :created
        else
          Rails.logger.error("[WorkoutSessionCreateError] user=#{current_user.id} errors=#{session.errors.full_messages.inspect}")
          render json: { errors: session.errors.full_messages }, status: :unprocessable_entity
        end
      rescue => e
        Rails.logger.error("[WorkoutSessionCreateError] #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        render json: { errors: [e.message] }, status: :unprocessable_entity
      end

      def stats
        sessions = current_user.workout_sessions.order(completed_at: :desc)
        range      = Progress::WeekRange.current
        week_start = range.begin.beginning_of_day
        week_end   = range.end.end_of_day
        weekly = sessions.select { |s| s.completed_at >= week_start && s.completed_at <= week_end }
        goal = current_user.health_profile&.training_days_per_week || 3
        total_volume = calculate_total_volume(sessions)
        streak_svc = WorkoutStreakService.new(sessions)

        recent_sessions = sessions.first(10)
        dominant_modality = detect_dominant_modality(recent_sessions)
        modality_stats = calculate_modality_stats(sessions.first(30), dominant_modality)

        recent_fatigues = current_user.workout_sessions
          .where("completed_at >= ?", 14.days.ago)
          .where.not(fatigue_level: nil)
          .pluck(:fatigue_level)
        prev_fatigues = current_user.workout_sessions
          .where(completed_at: 28.days.ago..14.days.ago)
          .where.not(fatigue_level: nil)
          .pluck(:fatigue_level)
        fatigue_avg = recent_fatigues.any? ? (recent_fatigues.sum.to_f / recent_fatigues.size).round(1) : nil
        fatigue_trend = if recent_fatigues.any? && prev_fatigues.any?
          prev_avg = prev_fatigues.sum.to_f / prev_fatigues.size
          ((fatigue_avg - prev_avg) / prev_avg * 100).round
        end
        suggest_deload = fatigue_avg.present? && fatigue_avg >= 4.0 && recent_fatigues.size >= 3

        calories_week = weekly.sum { |s| s.calories_estimated.to_i }
        sessions_last_30_days = current_user.workout_sessions
          .where("completed_at >= ?", 30.days.ago).count

        render json: {
          total_sessions: sessions.count,
          sessions_last_30_days: sessions_last_30_days,
          streak: streak_svc.current_streak,
          best_streak: streak_svc.best_streak,
          last_activity_at: streak_svc.last_activity_at,
          weekly_sessions: weekly.count,
          weekly_goal: goal,
          total_volume_kg: total_volume,
          weekly_session_dates: weekly.map { |s| s.completed_at.iso8601 },
          dominant_modality: dominant_modality,
          modality_stats: modality_stats,
          fatigue_avg: fatigue_avg,
          fatigue_trend: fatigue_trend,
          suggest_deload: suggest_deload,
          calories_week: calories_week
        }
      end

      def last_performances
        exercise_ids = params[:exercise_ids].to_s.split(",").map(&:to_i)
        return render json: {} if exercise_ids.blank?

        recent = current_user.workout_sessions
          .where("exercise_logs IS NOT NULL AND exercise_logs != '[]'::jsonb")
          .order(completed_at: :desc)
          .limit(30)
          .select(:id, :exercise_logs, :completed_at)

        result = {}
        exercise_ids.each do |ex_id|
          session = recent.find { |s| (s.exercise_logs || []).any? { |l| l["exercise_id"] == ex_id } }
          next unless session

          log = (session.exercise_logs || []).find { |l| l["exercise_id"] == ex_id }
          next unless log

          result[ex_id.to_s] = {
            weight_by_set:    log["weight_by_set"] || [],
            reps:             log["reps"] || [],
            sets:             log["sets"],
            feeling:          log["feeling"],
            duration_minutes: log["duration_minutes"],
            elapsed_seconds:  log["elapsed_seconds"],
            intensity:        log["intensity"],
            completed_at:     session.completed_at
          }
        end

        render json: result
      end

      def monthly_summary
        start_date = 6.months.ago.beginning_of_month
        sessions = current_user.workout_sessions
          .where("completed_at >= ?", start_date)
          .select(:completed_at, :exercise_logs, :duration_minutes)

        by_month = sessions.group_by { |s| s.completed_at.beginning_of_month }
        result = (0...6).map do |i|
          month = i.months.ago.beginning_of_month
          month_sessions = by_month[month] || []
          volume = month_sessions.sum do |s|
            (s.exercise_logs || []).sum do |log|
              ws = log["weight_by_set"] || (log["weight_kg"] ? [log["weight_kg"]] : [])
              rs = log["reps"].is_a?(Array) ? log["reps"] : Array.new(log["sets"].to_i, log["reps"].to_i)
              ws.each_with_index.sum { |w, idx| (w || 0).to_f * (rs[idx] || 0).to_f }
            end
          end
          {
            month: month.strftime("%Y-%m"),
            label: I18n.l(month, format: "%b/%y"),
            sessions: month_sessions.size,
            volume_kg: volume.round
          }
        end.reverse

        render json: result
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
            next unless log["exercise_id"]
            ex_id = log["exercise_id"]
            warmup_flags = Array(log["is_warmup_by_set"])
            weights = Array(log["weight_by_set"])

            max_normal_weight = if weights.any?
              weights.each_with_index.filter_map { |w, i| w.to_f if w.to_f > 0 && !warmup_flags[i] }.max
            elsif log["weight_kg"].to_f > 0 && !warmup_flags[0]
              log["weight_kg"].to_f
            end

            next unless max_normal_weight

            if records[ex_id].nil? || max_normal_weight > records[ex_id][:max_weight_kg]
              records[ex_id] = {
                exercise_id: ex_id,
                exercise_name: log["name"],
                max_weight_kg: max_normal_weight,
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
          :source,
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
            :elapsed_seconds,
            :target_seconds,
            :distance_km,
            :avg_speed_kmh,
            :avg_pace_per_km,
            weight_by_set: [],
            is_warmup_by_set: [],
            reps: []
          ]
        )
      end

      def session_json(s)
        {
          id: s.id,
          workout_day_id: s.workout_day_id,
          workout_day_name: s.workout_day&.name,
          completed_at: s.completed_at,
          duration_minutes: s.duration_minutes,
          fatigue_level: s.fatigue_level,
          exercise_logs: s.exercise_logs || [],
          notes: s.notes,
          calories_estimated: s.calories_estimated
        }
      end

      def detect_dominant_modality(sessions)
        type_counts = Hash.new(0)
        sessions.each do |s|
          (s.exercise_logs || []).each do |log|
            t = log["exercise_type"] || "musculacao"
            type_counts[t] += 1
          end
        end
        return "musculacao" if type_counts.empty?

        raw = type_counts.max_by { |_, v| v }&.first
        case raw
        when "cardio", "corrida"   then "corrida"
        when "bike"                then "bike"
        when "caminhada"           then "caminhada"
        when "hiit"                then "hiit"
        when "timed"               then "timed"
        when "funcional"           then "funcional"
        else "musculacao"
        end
      end

      def calculate_modality_stats(sessions, modality)
        logs = sessions.flat_map { |s| s.exercise_logs || [] }

        case modality
        when "musculacao", "funcional"
          {
            total_volume_kg: calculate_total_volume(sessions),
            sessions_count: sessions.count
          }
        when "corrida", "bike", "caminhada", "cardio"
          durations = logs.filter_map { |l| l["duration_minutes"].to_f if l["duration_minutes"].to_f > 0 }
          distances = logs.filter_map { |l| l["distance_km"].to_f if l["distance_km"].to_f > 0 }
          {
            total_duration_minutes: durations.sum.round,
            total_distance_km: distances.sum.round(1),
            avg_speed_kmh: logs.filter_map { |l| l["avg_speed_kmh"].to_f if l["avg_speed_kmh"].to_f > 0 }.then { |sp| sp.any? ? (sp.sum / sp.size).round(1) : nil },
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
          { total_sessions: sessions.count }
        end
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
