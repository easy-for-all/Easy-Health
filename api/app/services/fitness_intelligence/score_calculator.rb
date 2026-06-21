module FitnessIntelligence
  class ScoreCalculator
    WINDOW_DAYS = 28
    HISTORY_DAYS = 90
    RECOVERY_WINDOW_DAYS = 14
    RECENT_WINDOW_DAYS = 7

    def initialize(user:, health_profile:, now: Time.current)
      @user = user
      @health_profile = health_profile
      @now = now
    end

    def call
      sessions_28 = sessions_since(WINDOW_DAYS)
      sessions_90 = sessions_since(HISTORY_DAYS)
      sessions_14 = sessions_since(RECOVERY_WINDOW_DAYS)
      active_days_28 = active_days(sessions_28)
      target_sessions = [ (@health_profile.training_days_per_week || 3) * 4, 1 ].max
      attendance_ratio = [ active_days_28.size.to_f / target_sessions, 1.0 ].min
      exercise_completion = exercise_completion_ratio(sessions_28)

      scores, status = build_scores(
        sessions_28: sessions_28,
        sessions_90: sessions_90,
        sessions_14: sessions_14,
        active_days_28: active_days_28,
        target_sessions: target_sessions,
        attendance_ratio: attendance_ratio,
        exercise_completion: exercise_completion
      )

      {
        scores: scores,
        training_maturity: training_maturity(sessions_90),
        breakdown: {
          window_days: WINDOW_DAYS,
          history_days: HISTORY_DAYS,
          target_sessions: target_sessions,
          active_days_28: active_days_28.size,
          completed_sessions_28: sessions_28.size,
          completed_sessions_90: sessions_90.size,
          attendance_ratio: attendance_ratio.round(3),
          exercise_completion_ratio: exercise_completion&.round(3),
          score_status: status
        }
      }
    end

    private

    def build_scores(sessions_28:, sessions_90:, sessions_14:, active_days_28:, target_sessions:, attendance_ratio:, exercise_completion:)
      no_history = sessions_28.empty?
      consistency = no_history ? 0 : score(attendance_ratio * 10)
      adherence = adherence_score(no_history, attendance_ratio, exercise_completion)
      recovery = recovery_score(sessions_14)
      mobility = mobility_score
      motivation = motivation_score(no_history, attendance_ratio)
      risk = risk_score(no_history)
      preference_confidence = preference_confidence_score
      behavior_confidence = behavior_confidence_score(sessions_90)

      [
        {
          consistency_score: consistency,
          adherence_score: adherence,
          recovery_score: recovery,
          mobility_score: mobility,
          motivation_score: motivation,
          risk_score: risk,
          preference_confidence_score: preference_confidence,
          behavior_confidence_score: behavior_confidence
        },
        {
          consistency_score: no_history ? "insufficient_data" : "observed",
          adherence_score: no_history ? "insufficient_data" : (exercise_completion ? "observed" : "attendance_only"),
          recovery_score: sessions_14.size < 3 ? "insufficient_data" : "observed",
          mobility_score: mobility_evidence_status,
          motivation_score: no_history ? "insufficient_data" : "observed",
          risk_score: "known_safety_signals",
          preference_confidence_score: "declared_preferences",
          behavior_confidence_score: sessions_90.empty? ? "insufficient_data" : "observed"
        }
      ]
    end

    def adherence_score(no_history, attendance_ratio, exercise_completion)
      return 5 if no_history
      return score(attendance_ratio * 10) unless exercise_completion

      score((attendance_ratio * 10 * 0.6) + (exercise_completion * 10 * 0.4))
    end

    def recovery_score(sessions_14)
      return 5 if sessions_14.size < 3

      score_value = 7.0
      active_days_7 = active_days(sessions_since(RECENT_WINDOW_DAYS))
      score_value -= 2 if active_days_7.size >= 6
      score_value -= 2 if longest_consecutive_streak(active_days(sessions_14)) >= 4

      fatigues = sessions_14.filter_map(&:fatigue_level)
      score_value -= 2 if fatigues.size >= 2 && (fatigues.sum.to_f / fatigues.size) >= 4
      score_value += 1 if active_days_7.size.between?(2, 5)
      score(score_value)
    end

    def mobility_score
      limitations_penalty = [ limitations.size, 3 ].min
      age_penalty = @health_profile.age.to_i >= 65 ? 1 : 0
      score(5 - limitations_penalty - age_penalty)
    end

    def mobility_evidence_status
      limitations.any? || @health_profile.age.present? ? "declared_context" : "not_assessed"
    end

    def motivation_score(no_history, attendance_ratio)
      return 5 if no_history

      score_value = attendance_ratio * 7
      score_value += 1 if @user.workout_sessions.where(completed_at: @now - RECENT_WINDOW_DAYS.days..@now).exists?
      score_value += 1 if @user.user_favorite_exercises.exists?
      score_value += 1 if @user.user_events.where(event_name: "progress_viewed", created_at: @now - WINDOW_DAYS.days..@now).exists?
      score(score_value)
    end

    def risk_score(no_history)
      score_value = 2.0
      age = @health_profile.age.to_i

      score_value += 2 if @health_profile.fitness_level == "beginner"
      score_value += 2 if age.positive? && age < 18
      score_value += 2 if age >= 60
      score_value += 2 if limitations.any?
      score_value += 2 if adult_bmi_caution?
      score_value += 1 if no_history

      score(score_value)
    end

    def preference_confidence_score
      score_value = 0
      score_value += 2 if @health_profile.goal.present? && @health_profile.fitness_level.present?
      score_value += 2 if Array(@health_profile.activity_preferences).any?
      score_value += 1 if @health_profile.training_location.present?
      score_value += 1 if Array(@health_profile.preferred_training_styles).any?
      score_value += 1 if limitations.any?
      score_value += [ @user.user_training_preferences.count, 3 ].min
      score(score_value)
    end

    def behavior_confidence_score(sessions_90)
      distinct_exercise_ids = sessions_90.flat_map { |session| Array(session.exercise_logs).filter_map { |log| log["exercise_id"] } }.uniq
      swap_feedback_count = @user.user_training_preferences.where(source: "swap_feedback").count
      score((sessions_90.size / 2.0) + [ distinct_exercise_ids.size / 5.0, 3 ].min + [ swap_feedback_count, 2 ].min)
    end

    def training_maturity(sessions_90)
      base = { "beginner" => 2, "intermediate" => 6, "advanced" => 9 }.fetch(@health_profile.fitness_level, 2)
      activity_bonus = [ active_days(sessions_90).size.to_f / 20, 1 ].min
      score(base + activity_bonus)
    end

    def exercise_completion_ratio(sessions)
      paired_sessions = sessions.select { |session| session.workout_day.present? && session.workout_day.workout_day_exercises.any? }
      return nil if paired_sessions.empty?

      planned = paired_sessions.sum { |session| session.workout_day.workout_day_exercises.size }
      return nil if planned.zero?

      completed = paired_sessions.sum { |session| [ Array(session.exercise_logs).size, session.workout_day.workout_day_exercises.size ].min }
      [ completed.to_f / planned, 1.0 ].min
    end

    def sessions_since(days)
      @user.workout_sessions
        .where(completed_at: @now - days.days..@now)
        .includes(workout_day: :workout_day_exercises)
        .to_a
    end

    def active_days(sessions)
      sessions.filter_map { |session| session.completed_at&.in_time_zone&.to_date }.uniq.sort
    end

    def longest_consecutive_streak(days)
      return 0 if days.empty?

      longest = 1
      current = 1
      days.each_cons(2) do |previous_day, current_day|
        current = current_day == previous_day + 1 ? current + 1 : 1
        longest = [ longest, current ].max
      end
      longest
    end

    def adult_bmi_caution?
      return false unless @health_profile.age.to_i >= 18

      weight = @health_profile.weight_kg.to_f
      height_meters = @health_profile.height_cm.to_f / 100
      return false if weight <= 0 || height_meters <= 0

      (weight / (height_meters**2)) >= 30
    end

    def limitations
      Array(@health_profile.limitations).map { |limitation| limitation.to_s.strip }.reject(&:blank?)
    end

    def score(value)
      value.to_f.clamp(0, 10).round(2)
    end
  end
end
