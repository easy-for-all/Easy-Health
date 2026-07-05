class LoadProgressionService
  SESSIONS_NEEDED = 2
  MAX_FATIGUE_FOR_INCREASE = 3
  MAX_DAYS_SINCE_LAST = 10

  def initialize(user:, exercise_id:)
    @user = user
    @exercise_id = exercise_id.to_i
    @sessions = fetch_relevant_sessions
  end

  def call
    return insufficient_data if @sessions.length < SESSIONS_NEEDED

    last = @sessions.first
    prev = @sessions.second

    last_log = find_exercise_log(last)
    prev_log = find_exercise_log(prev)
    return insufficient_data unless last_log && prev_log

    last_weight = avg_weight(last_log)
    last_reps = total_reps(last_log)
    prev_reps = total_reps(prev_log)
    last_planned_sets = last_log["planned_sets"].to_i
    last_completed_sets = completed_sets(last_log)
    last_fatigue = last.fatigue_level.to_i
    last_completion = last.completion_status || "completed"
    days_since = (Date.today - last.completed_at.to_date).to_i

    return too_long_since if days_since > MAX_DAYS_SINCE_LAST
    return high_fatigue(last_weight) if last_fatigue >= 4
    return partial_workout(last_weight) if last_completion != "completed"
    return reps_dropped(last_weight) if last_reps < prev_reps
    return sets_incomplete(last_weight) if last_planned_sets > 0 && last_completed_sets < last_planned_sets

    if consistent_performance?(last_log, prev_log)
      suggest_increase(last_weight)
    else
      maintain(last_weight)
    end
  end

  private

  def fetch_relevant_sessions
    @user.workout_sessions
      .where(status: "completed")
      .where("exercise_logs @> ?", [{ exercise_id: @exercise_id }].to_json)
      .order(completed_at: :desc)
      .limit(5)
  end

  def find_exercise_log(session)
    (session.exercise_logs || []).find { |log| log["exercise_id"].to_i == @exercise_id }
  end

  def avg_weight(log)
    weights = (log["weight_by_set"] || [log["weight_kg"]]).compact.map(&:to_f).reject(&:zero?)
    weights.any? ? (weights.sum / weights.size).round(1) : 0.0
  end

  def total_reps(log)
    reps = log["reps"] || []
    reps.map(&:to_i).sum
  end

  def completed_sets(log)
    reps = log["reps"] || []
    reps.map(&:to_i).count(&:positive?)
  end

  def consistent_performance?(last_log, prev_log)
    last_reps = total_reps(last_log)
    prev_reps = total_reps(prev_log)
    last_weight = avg_weight(last_log)
    prev_weight = avg_weight(prev_log)

    last_reps >= prev_reps && last_weight >= prev_weight
  end

  def suggest_increase(current_weight)
    increment = current_weight < 10 ? 0.5 : current_weight < 30 ? 1.25 : 2.5
    suggested = (current_weight + increment).round(2)
    {
      action: "increase",
      suggested_weight: suggested,
      current_weight: current_weight,
      reason: "Execução consistente nas últimas #{SESSIONS_NEEDED} sessões. Teste #{suggested}kg mantendo controle total.",
    }
  end

  def maintain(current_weight)
    {
      action: "maintain",
      suggested_weight: current_weight,
      current_weight: current_weight,
      reason: "Mantenha #{current_weight}kg e foque em execução limpa.",
    }
  end

  def high_fatigue(current_weight)
    {
      action: "maintain",
      suggested_weight: current_weight,
      current_weight: current_weight,
      reason: "Fadiga elevada no último treino. Mantenha #{current_weight}kg e priorize recuperação.",
    }
  end

  def partial_workout(current_weight)
    {
      action: "maintain",
      suggested_weight: current_weight,
      current_weight: current_weight,
      reason: "Último treino foi parcial. Mantenha #{current_weight}kg e conclua o treino completo antes de progredir.",
    }
  end

  def reps_dropped(current_weight)
    {
      action: "maintain",
      suggested_weight: current_weight,
      current_weight: current_weight,
      reason: "As repetições caíram em relação à sessão anterior. Consolide #{current_weight}kg antes de aumentar.",
    }
  end

  def sets_incomplete(current_weight)
    {
      action: "maintain",
      suggested_weight: current_weight,
      current_weight: current_weight,
      reason: "Séries incompletas no último treino. Complete todas as séries com #{current_weight}kg primeiro.",
    }
  end

  def too_long_since(current_weight = 0)
    {
      action: "maintain",
      suggested_weight: current_weight,
      current_weight: current_weight,
      reason: "Longo intervalo desde o último treino. Retome com carga conservadora e ajuste conforme sentir.",
    }
  end

  def insufficient_data
    {
      action: "maintain",
      suggested_weight: nil,
      current_weight: nil,
      reason: "Dados insuficientes para sugerir progressão.",
    }
  end
end
