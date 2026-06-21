module CoachEngine
  class BehaviorAnalyst
    HISTORY_DAYS = 90
    MINIMUM_SESSIONS = 3
    MINIMUM_SKIPPED_EXPOSURES = 3
    MINIMUM_PREFERENCE_SIGNALS = 6
    DOMINANCE_THRESHOLD = 0.6
    LOWER_MUSCLE_GROUPS = %w[legs glutes calves].freeze
    UPPER_MUSCLE_GROUPS = %w[chest back shoulders biceps triceps forearms trapezius].freeze
    CARDIO_TYPES = %w[cardio corrida caminhada hiit natacao].freeze

    def initialize(user:, fitness_profile:, health_profile: nil, now: Time.current)
      @user = user
      @fitness_profile = fitness_profile
      @health_profile = health_profile || user.health_profile
      @now = now
    end

    def call
      result = observations
      {
        "behavior_pattern" => primary_pattern(result),
        "preferred_patterns" => result[:preferred_patterns],
        "avoided_patterns" => result[:avoided_patterns],
        "adherence_notes" => result[:adherence_notes],
        "confidence" => confidence(result),
        "explanation" => explanation_for(primary_pattern(result)),
        "evidence" => result[:evidence]
      }
    end

    private

    def observations
      return insufficient_data_observations if sessions.size < MINIMUM_SESSIONS

      skipped = skipped_pattern_counts
      preferred = preferred_patterns
      avoided = skipped.filter_map do |pattern, count|
        pattern if count[:planned] >= MINIMUM_SKIPPED_EXPOSURES && count[:skipped].to_f / count[:planned] >= 0.5
      end

      {
        preferred_patterns: preferred,
        avoided_patterns: avoided,
        adherence_notes: adherence_notes(avoided),
        evidence: {
          "session_count" => sessions.size,
          "median_duration_minutes" => median_duration,
          "skipped_pattern_counts" => skipped.transform_values { |count| { "planned" => count[:planned], "skipped" => count[:skipped] } },
          "suggestion_feedback_count" => accepted_suggestion_count,
          "swap_feedback_count" => swap_feedback_count
        }
      }
    end

    def insufficient_data_observations
      {
        preferred_patterns: substitution_signals,
        avoided_patterns: [],
        adherence_notes: [ "São necessárias ao menos três sessões para identificar padrões de treino confiáveis." ],
        evidence: {
          "session_count" => sessions.size,
          "suggestion_feedback_count" => accepted_suggestion_count,
          "swap_feedback_count" => swap_feedback_count
        }
      }
    end

    def primary_pattern(result)
      return "unknown" if sessions.size < MINIMUM_SESSIONS

      patterns = result[:avoided_patterns] + result[:preferred_patterns]
      return "skips_lower_body" if patterns.include?("skips_lower_body")
      return "skips_upper_body" if patterns.include?("skips_upper_body")
      return "skips_cardio" if patterns.include?("skips_cardio")
      return "low_adherence" if @fitness_profile.adherence_score.to_f < 4
      return "inconsistent_usage" if @fitness_profile.consistency_score.to_f < 4
      return "consistent_short_sessions" if patterns.include?("consistent_short_sessions")
      return "prefers_machines" if patterns.include?("prefers_machines")
      return "prefers_free_weights" if patterns.include?("prefers_free_weights")
      return "prefers_cardio" if patterns.include?("prefers_cardio")
      return "prefers_bodyweight" if patterns.include?("prefers_bodyweight")
      return "weekend_only" if patterns.include?("weekend_only")
      return "morning_training" if patterns.include?("morning_training")
      return "evening_training" if patterns.include?("evening_training")
      return "high_adherence" if @fitness_profile.adherence_score.to_f >= 8

      "unknown"
    end

    def preferred_patterns
      patterns = []
      patterns << "consistent_short_sessions" if sessions.size >= 4 && median_duration <= 35 && @fitness_profile.adherence_score.to_f >= 6
      patterns.concat(modality_preference_patterns)
      patterns << "weekend_only" if weekend_ratio >= 0.75 && sessions.size >= 4
      patterns << "morning_training" if time_of_day_ratio(:morning) >= 0.75 && sessions.size >= 4
      patterns << "evening_training" if time_of_day_ratio(:evening) >= 0.75 && sessions.size >= 4
      patterns.concat(substitution_signals)
      patterns.uniq
    end

    def skipped_pattern_counts
      counts = Hash.new { |hash, key| hash[key] = { planned: 0, skipped: 0 } }

      sessions.each do |session|
        day = session.workout_day
        next unless day

        logged_ids = Array(session.exercise_logs).filter_map { |log| id = log["exercise_id"].to_i; id if id.positive? }.to_set
        day.workout_day_exercises.each do |workout_day_exercise|
          pattern = skipped_pattern_for(workout_day_exercise.exercise)
          next unless pattern

          counts[pattern][:planned] += 1
          counts[pattern][:skipped] += 1 unless logged_ids.include?(workout_day_exercise.exercise_id)
        end
      end

      counts
    end

    def skipped_pattern_for(exercise)
      return "skips_cardio" if CARDIO_TYPES.include?(exercise.exercise_type)
      return "skips_lower_body" if exercise.muscle_group.in?(LOWER_MUSCLE_GROUPS)
      "skips_upper_body" if exercise.muscle_group.in?(UPPER_MUSCLE_GROUPS)
    end

    def modality_preference_patterns
      exercise_ids = completed_exercise_ids
      return [] if exercise_ids.size < MINIMUM_PREFERENCE_SIGNALS

      exercises = Exercise.where(id: exercise_ids).pluck(:id, :equipment_type, :exercise_type).to_h do |id, equipment, exercise_type|
        [ id, { equipment: equipment, type: exercise_type } ]
      end
      counts = Hash.new(0)
      exercise_ids.each do |id|
        exercise = exercises[id]
        next unless exercise

        counts[:machine] += 1 if exercise[:equipment] == "machine"
        counts[:free_weights] += 1 if exercise[:equipment].in?(%w[dumbbell barbell cable])
        counts[:bodyweight] += 1 if exercise[:equipment] == "bodyweight"
        counts[:cardio] += 1 if CARDIO_TYPES.include?(exercise[:type])
      end

      total = exercise_ids.size.to_f
      patterns = []
      patterns << "prefers_machines" if counts[:machine] / total >= DOMINANCE_THRESHOLD
      patterns << "prefers_free_weights" if counts[:free_weights] / total >= DOMINANCE_THRESHOLD
      patterns << "prefers_bodyweight" if counts[:bodyweight] / total >= DOMINANCE_THRESHOLD
      patterns << "prefers_cardio" if counts[:cardio] / total >= DOMINANCE_THRESHOLD
      patterns
    end

    def substitution_signals
      return [] if accepted_suggestion_count.zero? && swap_feedback_count.zero?

      [ "responds_to_substitution_feedback" ]
    end

    def adherence_notes(avoided_patterns)
      notes = []
      notes << "A execução recente está abaixo da frequência planejada." if @fitness_profile.adherence_score.to_f < 4
      notes << "Há variação alta na recorrência de treino." if @fitness_profile.consistency_score.to_f < 4
      notes << "Pulos recorrentes foram inferidos apenas em sessões vinculadas a um plano." if avoided_patterns.any?
      notes << "Feedback de troca foi tratado como preferência, não como substituição executada." if substitution_signals.any?
      notes.presence || [ "A recorrência recente não mostra um padrão de aderência crítico." ]
    end

    def confidence(result)
      return 0.2 if sessions.size < MINIMUM_SESSIONS

      planned_observations = result.dig(:evidence, "skipped_pattern_counts").to_h.values.sum { |count| count["planned"].to_i }
      value = 0.35 + [ sessions.size.to_f / 15, 0.35 ].min + [ planned_observations.to_f / 20, 0.2 ].min
      value += 0.1 if accepted_suggestion_count.positive? || swap_feedback_count.positive?
      value.clamp(0, 0.95).round(2)
    end

    def explanation_for(pattern)
      {
        "unknown" => "Ainda não há sessões suficientes para identificar um padrão de treino confiável.",
        "skips_lower_body" => "Sessões vinculadas ao plano indicam pulos recorrentes de membros inferiores.",
        "skips_upper_body" => "Sessões vinculadas ao plano indicam pulos recorrentes de membros superiores.",
        "skips_cardio" => "Sessões vinculadas ao plano indicam pulos recorrentes de cardio.",
        "low_adherence" => "A recorrência recente está abaixo da frequência planejada.",
        "inconsistent_usage" => "A frequência recente de treino é irregular.",
        "consistent_short_sessions" => "As sessões concluídas são curtas e recorrentes.",
        "prefers_machines" => "As execuções recentes são predominantemente em máquinas.",
        "prefers_free_weights" => "As execuções recentes são predominantemente com pesos livres.",
        "prefers_cardio" => "As execuções recentes são predominantemente cardiovasculares.",
        "prefers_bodyweight" => "As execuções recentes são predominantemente com peso corporal.",
        "weekend_only" => "A maior parte das sessões recentes ocorreu no fim de semana.",
        "morning_training" => "A maior parte das sessões recentes foi concluída pela manhã.",
        "evening_training" => "A maior parte das sessões recentes foi concluída à noite.",
        "high_adherence" => "A frequência recente está alinhada ao plano informado."
      }.fetch(pattern)
    end

    def sessions
      @sessions ||= @user.workout_sessions
        .where(completed_at: @now - HISTORY_DAYS.days..@now)
        .includes(workout_day: { workout_day_exercises: :exercise })
        .order(completed_at: :desc)
        .to_a
    end

    def completed_exercise_ids
      @completed_exercise_ids ||= sessions.flat_map do |session|
        Array(session.exercise_logs).filter_map { |log| id = log["exercise_id"].to_i; id if id.positive? }
      end
    end

    def median_duration
      durations = sessions.filter_map(&:duration_minutes).sort
      return 0 if durations.empty?

      middle = durations.size / 2
      durations.size.odd? ? durations[middle] : (durations[middle - 1] + durations[middle]) / 2.0
    end

    def weekend_ratio
      sessions.count { |session| session.completed_at.saturday? || session.completed_at.sunday? }.to_f / sessions.size
    end

    def time_of_day_ratio(period)
      matching = sessions.count do |session|
        hour = session.completed_at.hour
        period == :morning ? hour < 12 : hour >= 17
      end
      matching.to_f / sessions.size
    end

    def accepted_suggestion_count
      @accepted_suggestion_count ||= @user.exercise_suggestion_logs.accepted.where(created_at: @now - HISTORY_DAYS.days..@now).count
    end

    def swap_feedback_count
      @swap_feedback_count ||= @user.user_training_preferences.where(source: "swap_feedback").count
    end
  end
end
