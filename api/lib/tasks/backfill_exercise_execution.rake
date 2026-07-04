def exercise_kind_for_legacy_log(log, exercise)
  return "timed" if log["target_seconds"].present? || log["elapsed_seconds"].present?
  return "cardio" if log["duration_minutes"].present? && log["weight_by_set"].blank? && log["reps"].blank?
  return "timed" if exercise && WorkoutDayExercise::TIMED_TYPES.include?(exercise.exercise_type)
  return "cardio" if exercise && WorkoutDayExercise::CARDIO_TYPES.include?(exercise.exercise_type)

  "strength"
end

namespace :exercise_execution do
  desc "Backfill exercise_sessions/exercise_sets from legacy workout_sessions.exercise_logs. Idempotent, safe to re-run. Use USER_ID=<id> to target one user."
  task backfill: :environment do
    scope = WorkoutSession
      .where("exercise_logs IS NOT NULL AND exercise_logs != '[]'::jsonb")
      .left_joins(:exercise_sessions)
      .where(exercise_sessions: { id: nil })
      .distinct
    scope = scope.where(user_id: ENV.fetch("USER_ID")) if ENV["USER_ID"].present?

    processed = 0
    failed = 0
    skipped_malformed = 0
    exercise_sessions_created = 0
    exercise_sets_created = 0

    scope.find_each(batch_size: 50) do |session|
      ActiveRecord::Base.transaction do
        Array(session.exercise_logs).each_with_index do |log, index|
          exercise_id = log["exercise_id"]
          exercise = exercise_id.present? ? Exercise.find_by(id: exercise_id) : nil

          if exercise_id.blank? || exercise.nil?
            skipped_malformed += 1
            next
          end

          kind = exercise_kind_for_legacy_log(log, exercise)

          exercise_session = session.exercise_sessions.create!(
            workout_day_exercise_id: log["workout_day_exercise_id"].presence,
            exercise_id: exercise_id,
            order_index: index,
            status: "completed",
            exercise_kind: kind,
            planned_sets: log["planned_sets"],
            rest_seconds: log["rest_seconds"],
            feeling: log["feeling"],
            duration_minutes: log["duration_minutes"],
            intensity: log["intensity"],
            elapsed_seconds: log["elapsed_seconds"],
            target_seconds: log["target_seconds"],
            distance_km: log["distance_km"],
            avg_speed_kmh: log["avg_speed_kmh"],
            avg_pace_per_km: log["avg_pace_per_km"],
            # Legacy sessions only ever recorded a single end-of-workout
            # timestamp, so started_at is approximated from completed_at.
            started_at: session.completed_at,
            completed_at: session.completed_at
          )
          exercise_sessions_created += 1

          next unless kind == "strength"

          entry = ExerciseLogEntry.new(log)
          set_count = [ entry.weight_by_set.size, entry.reps_by_set.size, entry.warmup_by_set.size ].max

          if set_count.zero? && log["weight_kg"].to_f > 0
            exercise_session.exercise_sets.create!(
              set_number: 1,
              weight_kg: log["weight_kg"],
              reps: log["reps"].is_a?(Integer) ? log["reps"] : nil,
              is_warmup: false,
              completed_at: session.completed_at
            )
            exercise_sets_created += 1
          else
            set_count.times do |set_index|
              exercise_session.exercise_sets.create!(
                set_number: set_index + 1,
                weight_kg: entry.weight_by_set[set_index],
                reps: entry.reps_by_set[set_index],
                is_warmup: entry.warmup_by_set[set_index] || false,
                completed_at: session.completed_at
              )
              exercise_sets_created += 1
            end
          end
        end
      end
      processed += 1
    rescue StandardError => e
      failed += 1
      Rails.logger.error("[ExerciseExecutionBackfill] session_id=#{session.id} #{e.class}: #{e.message}")
    end

    puts "#{processed} processed, #{failed} failed, #{skipped_malformed} skipped (malformed logs), " \
         "#{exercise_sessions_created} exercise_sessions, #{exercise_sets_created} exercise_sets"
  end
end
