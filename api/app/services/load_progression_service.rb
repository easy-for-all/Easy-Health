class LoadProgressionService
  SESSIONS_NEEDED = 2
  MAX_FATIGUE_FOR_INCREASE = 3
  MAX_DAYS_SINCE_LAST = 10

  Performance = Struct.new(
    :completed_at,
    :weight,
    :total_reps,
    :planned_sets,
    :completed_sets,
    :fatigue_level,
    :completion_status,
    :workout_session_id,
    keyword_init: true
  )

  def initialize(user:, exercise_id:)
    @user = user
    @exercise_id = exercise_id.to_i
    @performances = fetch_relevant_performances
  end

  def call
    return insufficient_data if @performances.empty?

    last = @performances.first
    return insufficient_data unless positive_weight?(last.weight)
    return first_record(last.weight) if @performances.length < SESSIONS_NEEDED

    prev = @performances.second
    return first_record(last.weight) unless prev && positive_weight?(prev.weight)

    days_since = (Date.current - last.completed_at.to_date).to_i
    return too_long_since(last.weight) if days_since > MAX_DAYS_SINCE_LAST
    return high_fatigue(last.weight) if last.fatigue_level.to_i >= 4
    return sets_incomplete(last.weight) if last.planned_sets.to_i > 0 && last.completed_sets.to_i < last.planned_sets.to_i
    return progressed(last.weight, prev.weight) if last.weight.to_f > prev.weight.to_f
    return reduced_load(last.weight, prev.weight) if last.weight.to_f < prev.weight.to_f
    return reps_dropped(last.weight) if last.total_reps.to_i < prev.total_reps.to_i

    if consistent_performance?(last, prev)
      suggest_increase(last.weight)
    else
      maintain(last.weight)
    end
  end

  private

  def fetch_relevant_performances
    relational = relational_performances
    relational_session_ids = relational.map(&:workout_session_id)
    legacy = legacy_performances(except_session_ids: relational_session_ids)

    (relational + legacy)
      .sort_by(&:completed_at)
      .reverse
      .first(5)
  end

  def relational_performances
    ExerciseSession
      .joins(:workout_session)
      .includes(:exercise_sets, :workout_session)
      .where(exercise_id: @exercise_id, status: "completed")
      .where(workout_sessions: { user_id: @user.id, status: "completed", completion_status: "completed" })
      .order("workout_sessions.completed_at DESC")
      .limit(5)
      .filter_map { |exercise_session| performance_from_exercise_session(exercise_session) }
  end

  def legacy_performances(except_session_ids:)
    scope = @user.workout_sessions
      .where(status: "completed", completion_status: "completed")
      .where("exercise_logs @> ?", [{ exercise_id: @exercise_id }].to_json)
      .order(completed_at: :desc)
      .limit(5)
    scope = scope.where.not(id: except_session_ids) if except_session_ids.any?

    scope.filter_map { |session| performance_from_legacy_session(session) }
  end

  def performance_from_exercise_session(exercise_session)
    sets = exercise_session.exercise_sets.sort_by(&:set_number)
    weight = representative_weight_from_sets(sets)
    return nil unless positive_weight?(weight)

    Performance.new(
      completed_at: exercise_session.workout_session.completed_at,
      weight: weight.to_f,
      total_reps: sets.sum { |set| set.reps.to_i },
      planned_sets: exercise_session.planned_sets.to_i,
      completed_sets: sets.count,
      fatigue_level: exercise_session.workout_session.fatigue_level,
      completion_status: exercise_session.workout_session.completion_status,
      workout_session_id: exercise_session.workout_session_id
    )
  end

  def performance_from_legacy_session(session)
    log = Array(session.exercise_logs).find { |entry| entry["exercise_id"].to_i == @exercise_id }
    return nil unless log

    entry = ExerciseLogEntry.new(log, completed_at: session.completed_at)
    weight = entry.last_used_weight
    return nil unless positive_weight?(weight)

    Performance.new(
      completed_at: session.completed_at,
      weight: weight.to_f,
      total_reps: entry.total_reps,
      planned_sets: entry.planned_sets.to_i,
      completed_sets: entry.completed_sets_count,
      fatigue_level: session.fatigue_level,
      completion_status: session.completion_status,
      workout_session_id: session.id
    )
  end

  def representative_weight_from_sets(sets)
    working = sets.select { |set| !set.is_warmup && positive_weight?(set.weight_kg) }
    fallback = sets.select { |set| positive_weight?(set.weight_kg) }

    (working.last || fallback.last)&.weight_kg
  end

  def positive_weight?(value)
    value.to_f.positive?
  end

  def consistent_performance?(last, prev)
    last.total_reps.to_i >= prev.total_reps.to_i && last.weight.to_f >= prev.weight.to_f
  end

  def suggest_increase(current_weight)
    suggested = round_to_supported_increment(current_weight.to_f + increment_for(current_weight))
    {
      action: "increase",
      progression_type: "increase_suggested",
      suggested_weight: suggested,
      current_weight: current_weight.to_f,
      reason: "Boa consistência! Você manteve #{format_weight(current_weight)} com controle. Teste #{format_weight(suggested)} no próximo treino.",
    }
  end

  def progressed(current_weight, previous_weight)
    {
      action: "progressed",
      progression_type: "progressed",
      suggested_weight: current_weight.to_f,
      current_weight: current_weight.to_f,
      previous_weight: previous_weight.to_f,
      reason: "Boa evolução! Você aumentou de #{format_weight(previous_weight)} para #{format_weight(current_weight)} neste exercício.",
    }
  end

  def first_record(current_weight)
    {
      action: "recorded",
      progression_type: "first_record",
      suggested_weight: current_weight.to_f,
      current_weight: current_weight.to_f,
      reason: "Carga registrada. Usaremos #{format_weight(current_weight)} como referência nos próximos treinos.",
    }
  end

  def maintain(current_weight)
    {
      action: "maintain",
      progression_type: "maintain",
      suggested_weight: current_weight.to_f,
      current_weight: current_weight.to_f,
      reason: "Boa consistência! Mantenha #{format_weight(current_weight)} com controle.",
    }
  end

  def high_fatigue(current_weight)
    {
      action: "maintain",
      progression_type: "fatigue",
      suggested_weight: current_weight.to_f,
      current_weight: current_weight.to_f,
      reason: "Fadiga elevada no último treino. Mantenha #{format_weight(current_weight)} e priorize recuperação.",
    }
  end

  def reps_dropped(current_weight)
    {
      action: "maintain",
      progression_type: "reps_dropped",
      suggested_weight: current_weight.to_f,
      current_weight: current_weight.to_f,
      reason: "As repetições caíram em relação à sessão anterior. Consolide #{format_weight(current_weight)} antes de aumentar.",
    }
  end

  def reduced_load(current_weight, previous_weight)
    {
      action: "maintain",
      progression_type: "reduced",
      suggested_weight: current_weight.to_f,
      current_weight: current_weight.to_f,
      previous_weight: previous_weight.to_f,
      reason: "Carga ajustada de #{format_weight(previous_weight)} para #{format_weight(current_weight)}. Mantenha uma execução segura.",
    }
  end

  def sets_incomplete(current_weight)
    {
      action: "maintain",
      progression_type: "sets_incomplete",
      suggested_weight: current_weight.to_f,
      current_weight: current_weight.to_f,
      reason: "Séries incompletas no último treino. Complete todas as séries com #{format_weight(current_weight)} primeiro.",
    }
  end

  def too_long_since(current_weight)
    {
      action: "maintain",
      progression_type: "long_break",
      suggested_weight: current_weight.to_f,
      current_weight: current_weight.to_f,
      reason: "Longo intervalo desde o último treino. Retome com #{format_weight(current_weight)} e ajuste conforme sentir.",
    }
  end

  def insufficient_data
    {
      action: "maintain",
      progression_type: "insufficient_data",
      suggested_weight: nil,
      current_weight: nil,
      reason: "Dados insuficientes para sugerir progressão.",
    }
  end

  def increment_for(current_weight)
    weight = current_weight.to_f
    return 5.0 if weight >= 60
    return 2.5 if weight >= 20

    1.0
  end

  def round_to_supported_increment(value)
    step = increment_for(value)
    rounded = (value.to_f / step).round * step
    rounded % 1 == 0 ? rounded.to_i : rounded.round(1)
  end

  def format_weight(value)
    number = value.to_f
    formatted = number % 1 == 0 ? number.to_i.to_s : number.round(1).to_s.tr(".", ",")
    "#{formatted} kg"
  end
end
