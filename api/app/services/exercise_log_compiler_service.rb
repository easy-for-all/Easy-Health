# Materializes workout_sessions.exercise_logs (the legacy JSONB format still
# read by mobile clients, CalorieEstimationService, FitnessIntelligence, etc.)
# from the relational exercise_sessions/exercise_sets rows recorded during a
# real-time execution. Used by WorkoutSessionsController#finish so the JSONB
# column stays a derived projection instead of the only source of truth.
class ExerciseLogCompilerService
  def initialize(workout_session)
    @workout_session = workout_session
  end

  def call
    exercise_sessions.map { |exercise_session| compile(exercise_session) }
  end

  private

  attr_reader :workout_session

  def exercise_sessions
    workout_session.exercise_sessions.includes(:exercise, :exercise_sets).order(:order_index)
  end

  def compile(exercise_session)
    if exercise_session.strength?
      compile_strength(exercise_session)
    else
      compile_timed_or_cardio(exercise_session)
    end
  end

  def compile_strength(exercise_session)
    sets = exercise_session.exercise_sets.sort_by(&:set_number)

    {
      "workout_day_exercise_id" => exercise_session.workout_day_exercise_id,
      "exercise_id" => exercise_session.exercise_id,
      "name" => exercise_session.exercise.name,
      "planned_sets" => exercise_session.planned_sets,
      "sets" => sets.size,
      "rest_seconds" => exercise_session.rest_seconds,
      "feeling" => exercise_session.feeling,
      "weight_kg" => sets.map(&:weight_kg).compact.first,
      "weight_by_set" => sets.map(&:weight_kg),
      "reps" => sets.map(&:reps),
      "is_warmup_by_set" => sets.map(&:is_warmup)
    }
  end

  def compile_timed_or_cardio(exercise_session)
    {
      "workout_day_exercise_id" => exercise_session.workout_day_exercise_id,
      "exercise_id" => exercise_session.exercise_id,
      "name" => exercise_session.exercise.name,
      "feeling" => exercise_session.feeling,
      "duration_minutes" => exercise_session.duration_minutes,
      "intensity" => exercise_session.intensity,
      "elapsed_seconds" => exercise_session.elapsed_seconds,
      "target_seconds" => exercise_session.target_seconds,
      "distance_km" => exercise_session.distance_km,
      "avg_speed_kmh" => exercise_session.avg_speed_kmh,
      "avg_pace_per_km" => exercise_session.avg_pace_per_km
    }
  end
end
