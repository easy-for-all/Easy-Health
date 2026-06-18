class CalorieEstimationService
  METS = {
    "musculacao" => 4.5,
    "cardio"     => 8.0,
    "corrida"    => 9.0,
    "hiit"       => 10.0,
    "funcional"  => 6.0,
    "natacao"    => 7.0,
    "caminhada"  => 3.5,
    "timed"      => 4.0,
  }.freeze

  DEFAULT_MET    = 5.0
  DEFAULT_WEIGHT = 70.0

  def initialize(duration_minutes:, workout_day:, user:)
    @duration_minutes = duration_minutes.to_f
    @workout_day      = workout_day
    @user             = user
  end

  def estimate
    return 0 if @duration_minutes <= 0

    met    = average_met
    weight = user_weight_kg
    hours  = @duration_minutes / 60.0

    (met * weight * hours).round
  end

  private

  def average_met
    types = @workout_day&.workout_day_exercises&.map { |wde|
      wde.exercise&.exercise_type
    }&.compact&.uniq || []

    return DEFAULT_MET if types.empty?

    values = types.map { |t| METS[t] || DEFAULT_MET }
    (values.sum.to_f / values.size).round(2)
  end

  def user_weight_kg
    @user.health_profile&.weight_kg&.to_f || DEFAULT_WEIGHT
  end
end
