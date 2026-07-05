class ExerciseGifAuditJob < ApplicationJob
  queue_as :default

  SIMILAR_THRESHOLD = 0.6

  def perform(dry_run: false)
    results = { kept: 0, replaced: 0, cleared: 0, invalid_workouts: 0 }

    Exercise.find_each do |exercise|
      if gif_valid?(exercise)
        results[:kept] += 1
      elsif (equivalent = find_equivalent(exercise))
        unless dry_run
          exercise.update_columns(
            gif_url: equivalent.gif_url,
            gif_path: equivalent.gif_path,
            image_url: nil
          )
        end
        results[:replaced] += 1
        Rails.logger.info "[ExerciseGifAuditJob] Replaced GIF for '#{exercise.name}' with '#{equivalent.name}'"
      else
        unless dry_run
          exercise.update_columns(gif_url: nil, gif_path: nil)
        end
        results[:cleared] += 1
        Rails.logger.info "[ExerciseGifAuditJob] Cleared GIF for '#{exercise.name}' (no equivalent found)"
      end
    end

    unless dry_run
      WorkoutDay.includes(workout_day_exercises: :exercise).find_each do |day|
        next if day.invalid_workout_reason.present?
        day.invalidate_if_needed!(equivalent_finder: method(:find_equivalent))
        results[:invalid_workouts] += 1 if day.reload.invalid_workout_reason.present?
      end
    end

    Rails.logger.info "[ExerciseGifAuditJob] Done: #{results.inspect}"
    results
  end

  private

  def gif_valid?(exercise)
    exercise.gifdotreino_source?
  end

  def find_equivalent(exercise)
    return nil if exercise.nil?

    normalized = normalize_name(exercise.name)

    Exercise.where.not(id: exercise.id)
            .merge(Exercise.gifdotreino_source)
            .find { |candidate| name_similarity(normalized, normalize_name(candidate.name)) >= SIMILAR_THRESHOLD }
  end

  def normalize_name(name)
    name.downcase
        .gsub(/[^a-z0-9\s]/, "")
        .gsub(/\s+/, " ")
        .strip
  end

  def name_similarity(a, b)
    words_a = a.split
    words_b = b.split
    return 0.0 if words_a.empty? || words_b.empty?

    intersection = words_a & words_b
    union        = (words_a | words_b)
    intersection.size.to_f / union.size
  end
end
