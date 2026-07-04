# Centralizes "what really happened with this exercise before" so the
# execution screen API and other endpoints stop re-deriving it independently.
# Every lookup here only ever considers workout_sessions with status
# "completed" - in_progress/cancelled sessions must never surface as history
# (this is the fix for sessions showing up as "done today" mid-execution).
#
# Reads the new relational exercise_sessions/exercise_sets first; falls back
# to parsing the legacy exercise_logs JSONB (via ExerciseLogEntry) for users/
# sessions that predate the backfill.
class ExerciseHistoryService
  def initialize(user:, exercise_id:)
    @user = user
    @exercise_id = exercise_id.to_i
  end

  def last_completed_session
    @last_completed_session ||= ExerciseSession
      .joins(:workout_session)
      .where(exercise_id: @exercise_id, status: "completed")
      .where(workout_sessions: { user_id: @user.id, status: "completed" })
      .order(completed_at: :desc)
      .first
  end

  def last_valid_working_set
    return nil unless last_completed_session

    sets = last_completed_session.exercise_sets
    sets.where(is_warmup: false).where.not(weight_kg: nil).order(set_number: :desc).first ||
      sets.where.not(weight_kg: nil).order(set_number: :desc).first
  end

  # Priority: last working set of a completed relational session > last set
  # of any kind in that session > legacy JSONB fallback for un-migrated data.
  def last_used_weight
    if last_completed_session
      last_valid_working_set&.weight_kg
    else
      legacy_entry&.last_used_weight
    end
  end

  def last_completed_at
    last_completed_session&.completed_at || legacy_session&.completed_at
  end

  def last_execution_label
    timestamp = last_completed_at
    return "Primeira vez neste exercício" unless timestamp

    case (Date.current - timestamp.to_date).to_i
    when ..0 then "Feito hoje"
    when 1 then "Feito ontem"
    else "Há #{(Date.current - timestamp.to_date).to_i} dias"
    end
  end

  def suggested_starting_weight
    progression[:suggested_weight]
  end

  def progression_reason
    progression[:reason]
  end

  # Normalized "what happened last time" summary, regardless of whether the
  # data lives in the relational tables or only in the legacy JSONB. Used by
  # endpoints that show set-by-set detail (not just a single weight/label).
  def last_performance_summary
    if last_completed_session
      sets = last_completed_session.exercise_sets.order(:set_number)
      {
        weight_by_set: sets.map(&:weight_kg),
        reps: sets.map(&:reps),
        sets: sets.size,
        feeling: last_completed_session.feeling,
        duration_minutes: last_completed_session.duration_minutes,
        elapsed_seconds: last_completed_session.elapsed_seconds,
        intensity: last_completed_session.intensity,
        completed_at: last_completed_session.completed_at
      }
    elsif legacy_entry
      {
        weight_by_set: legacy_entry.weight_by_set,
        reps: legacy_entry.reps_by_set,
        sets: legacy_entry.raw["sets"],
        feeling: legacy_entry.feeling,
        duration_minutes: legacy_entry.duration_minutes,
        elapsed_seconds: legacy_entry.elapsed_seconds,
        intensity: legacy_entry.intensity,
        completed_at: legacy_session.completed_at
      }
    end
  end

  def total_volume_for_session(workout_session)
    ExerciseSet
      .joins(:exercise_session)
      .where(exercise_sessions: { workout_session_id: workout_session.id }, is_warmup: false)
      .where.not(weight_kg: nil, reps: nil)
      .sum("weight_kg * reps")
  end

  # Best working weight ever recorded for this user/exercise, relational first
  # with a legacy-JSONB fallback for sessions not yet backfilled.
  def personal_record
    relational_best = ExerciseSet
      .joins(exercise_session: :workout_session)
      .where(exercise_sessions: { exercise_id: @exercise_id }, is_warmup: false)
      .where(workout_sessions: { user_id: @user.id, status: "completed" })
      .where.not(weight_kg: nil)
      .order(weight_kg: :desc, completed_at: :desc)
      .first

    return { max_weight_kg: relational_best.weight_kg, achieved_at: relational_best.completed_at } if relational_best

    legacy_personal_record
  end

  private

  def progression
    @progression ||= LoadProgressionService.new(user: @user, exercise_id: @exercise_id).call
  end

  def legacy_session
    @legacy_session ||= @user.workout_sessions
      .where(status: "completed")
      .where("exercise_logs @> ?", [ { exercise_id: @exercise_id } ].to_json)
      .order(completed_at: :desc)
      .first
  end

  def legacy_entry
    return nil unless legacy_session

    log = Array(legacy_session.exercise_logs).find { |l| l["exercise_id"].to_i == @exercise_id }
    return nil unless log

    ExerciseLogEntry.new(log)
  end

  def legacy_personal_record
    best = nil

    @user.workout_sessions
      .where(status: "completed")
      .where("exercise_logs @> ?", [ { exercise_id: @exercise_id } ].to_json)
      .find_each do |session|
        log = Array(session.exercise_logs).find { |l| l["exercise_id"].to_i == @exercise_id }
        next unless log

        max_weight = ExerciseLogEntry.new(log).max_working_weight
        next unless max_weight
        next if best && max_weight <= best[:max_weight_kg]

        best = { max_weight_kg: max_weight, achieved_at: session.completed_at }
      end

    best
  end
end
