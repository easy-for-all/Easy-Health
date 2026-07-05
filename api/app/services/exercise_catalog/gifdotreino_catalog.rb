require "set"

module ExerciseCatalog
  class GifdotreinoCatalog
    DEFAULT_ROOT = Rails.root.join("public", "exercise-images", "gifdotreino")
    SIMILARITY_THRESHOLD = 0.55

    GROUP_MAP = {
      "peitoral"        => { muscle_group: "chest",     exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "costas"          => { muscle_group: "back",      exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "ombros"          => { muscle_group: "shoulders", exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "biceps"          => { muscle_group: "biceps",    exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "triceps"         => { muscle_group: "triceps",   exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "pernas"          => { muscle_group: "legs",      exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "gluteos"         => { muscle_group: "glutes",    exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "panturrilhas"    => { muscle_group: "calves",    exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "trapezio"        => { muscle_group: "trapezius", exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "eretor-lombar"   => { muscle_group: "back",      exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "antebracos"      => { muscle_group: "forearms",  exercise_type: "musculacao", equipment_type: "gym",        home_compatible: false },
      "calistenia"      => { muscle_group: "core",      exercise_type: "funcional",  equipment_type: "bodyweight", home_compatible: true },
      "funcional-e-hit" => { muscle_group: "core",      exercise_type: "funcional",  equipment_type: "bodyweight", home_compatible: true },
      "mobilidade"      => { muscle_group: "core",      exercise_type: "timed",      equipment_type: "bodyweight", home_compatible: true },
      "crossfit"        => { muscle_group: "core",      exercise_type: "hiit",       equipment_type: "bodyweight", home_compatible: true },
      "cardio"          => { muscle_group: nil,          exercise_type: "cardio",     equipment_type: "cardio",     home_compatible: false }
    }.freeze

    attr_reader :root

    def initialize(root: DEFAULT_ROOT)
      @root = Pathname.new(root)
    end

    def sync!
      raise "gifdotreino directory not found: #{root}" unless root.directory?

      index = exercise_index
      report = { total_gifs: 0, created: 0, updated: 0, skipped: 0, errors: [] }

      gif_paths.each do |gif_path|
        report[:total_gifs] += 1
        attrs = attributes_for(gif_path)
        exercise = Exercise.find_by(gif_url: attrs[:gif_url]) || index[normalize(attrs[:name])]

        if exercise
          exercise.update!(attrs)
          report[:updated] += 1
        else
          exercise = Exercise.create!(attrs)
          report[:created] += 1
        end

        index[normalize(exercise.name)] = exercise
        index[normalize(exercise.name_en)] = exercise if exercise.name_en.present?
      rescue => e
        report[:skipped] += 1
        report[:errors] << { path: gif_path.to_s, error: e.message }
      end

      report
    end

    def purge_non_gifdotreino!(dry_run: true)
      valid_count = Exercise.gifdotreino_source.count
      raise "Cannot purge non-gifdotreino exercises before importing gifdotreino exercises" if !dry_run && valid_count.zero?

      report = purge_report(dry_run: dry_run, valid_count: valid_count)
      affected_day_ids = Set.new

      invalid_scope.find_each do |exercise|
        report[:scanned] += 1
        equivalent = find_equivalent(exercise)
        affected_day_ids.merge(WorkoutDayExercise.where(exercise_id: exercise.id).pluck(:workout_day_id))

        if equivalent
          reassign_exercise(exercise, equivalent, report, dry_run: dry_run)
        else
          remove_exercise(exercise, report, dry_run: dry_run)
        end
      end

      mark_empty_days_invalid(affected_day_ids, report) unless dry_run
      report
    end

    def invalid_scope
      Exercise.where("gif_url IS NULL OR gif_url NOT LIKE ?", Exercise::GIFDOTREINO_URL_PATTERN)
    end

    def find_equivalent(exercise)
      return nil unless exercise

      normalized = normalize(exercise.name)
      compatible_candidates(exercise).max_by do |candidate|
        name_similarity(normalized, normalize(candidate.name))
      end&.then do |candidate|
        name_similarity(normalized, normalize(candidate.name)) >= SIMILARITY_THRESHOLD ? candidate : nil
      end
    end

    private

    def gif_paths
      Dir.glob(root.join("**", "*.gif").to_s).sort
    end

    def attributes_for(gif_path)
      path = Pathname.new(gif_path)
      group_slug = path.dirname.basename.to_s
      name_slug = path.basename(".gif").to_s
      mapping = GROUP_MAP.fetch(group_slug) { { muscle_group: "core", exercise_type: "funcional", equipment_type: "bodyweight", home_compatible: true } }

      {
        name: display_name(name_slug),
        exercise_type: mapping[:exercise_type],
        muscle_group: mapping[:muscle_group],
        equipment_type: mapping[:equipment_type],
        home_compatible: mapping[:home_compatible],
        difficulty: "intermediate",
        difficulty_level: "intermediate",
        gif_url: "#{Exercise::GIFDOTREINO_URL_PREFIX}#{group_slug}/#{name_slug}.gif",
        gif_path: path.to_s,
        image_url: nil,
        image_fallback_url: nil,
        source_dataset: "gifdotreino"
      }
    end

    def display_name(name_slug)
      name_slug.tr("-", " ").split.map(&:capitalize).join(" ")
    end

    def exercise_index
      Exercise.all.each_with_object({}) do |exercise, index|
        index[normalize(exercise.name)] = exercise
        index[normalize(exercise.name_en)] = exercise if exercise.name_en.present?
      end
    end

    def compatible_candidates(exercise)
      @compatible_candidates ||= {}
      cache_key = [exercise.exercise_type, exercise.muscle_group]
      @compatible_candidates[cache_key] ||= begin
        scope = Exercise.gifdotreino_source.where.not(id: exercise.id)
        if exercise.muscle_group.present?
          scope = scope.where(muscle_group: exercise.muscle_group)
        else
          scope = scope.where(exercise_type: exercise.exercise_type)
        end
        scope.to_a
      end
    end

    def reassign_exercise(exercise, equivalent, report, dry_run:)
      report[:reassigned_exercises] += 1
      report[:workout_day_exercises_reassigned] += WorkoutDayExercise.where(exercise_id: exercise.id).count
      report[:exercise_sessions_reassigned] += ExerciseSession.where(exercise_id: exercise.id).count

      return if dry_run

      WorkoutDayExercise.where(exercise_id: exercise.id).update_all(exercise_id: equivalent.id, updated_at: Time.current)
      ExerciseSession.where(exercise_id: exercise.id).update_all(exercise_id: equivalent.id, updated_at: Time.current)
      reassign_favorites(exercise, equivalent, report)
      reassign_recommendations(exercise, equivalent, report)
      EquipmentIdentification.where(exercise_id: exercise.id).update_all(exercise_id: equivalent.id, updated_at: Time.current)
      replace_suggestion_log_refs(exercise.id, equivalent.id, report)
      replace_profile_refs(exercise.id, equivalent.id, report)
      replace_strategy_refs(exercise.id, equivalent.id, report)
      exercise.destroy!
    end

    def remove_exercise(exercise, report, dry_run:)
      report[:destroyed_exercises] += 1
      report[:workout_day_exercises_removed] += WorkoutDayExercise.where(exercise_id: exercise.id).count
      report[:exercise_sessions_removed] += ExerciseSession.where(exercise_id: exercise.id).count
      report[:favorites_removed] += UserFavoriteExercise.where(exercise_id: exercise.id).count

      return if dry_run

      WorkoutDayExercise.where(exercise_id: exercise.id).destroy_all
      ExerciseSession.where(exercise_id: exercise.id).destroy_all
      UserFavoriteExercise.where(exercise_id: exercise.id).destroy_all
      CoachRecommendation.where(exercise_id: exercise.id).update_all(exercise_id: nil, updated_at: Time.current)
      EquipmentIdentification.where(exercise_id: exercise.id).update_all(exercise_id: nil, updated_at: Time.current)
      replace_suggestion_log_refs(exercise.id, nil, report)
      replace_profile_refs(exercise.id, nil, report)
      replace_strategy_refs(exercise.id, nil, report)
      exercise.destroy!
    end

    def reassign_favorites(exercise, equivalent, report)
      UserFavoriteExercise.where(exercise_id: exercise.id).find_each do |favorite|
        if UserFavoriteExercise.exists?(user_id: favorite.user_id, exercise_id: equivalent.id)
          favorite.destroy!
          report[:favorites_removed] += 1
        else
          favorite.update!(exercise_id: equivalent.id)
          report[:favorites_reassigned] += 1
        end
      end
    end

    def reassign_recommendations(exercise, equivalent, report)
      CoachRecommendation.where(exercise_id: exercise.id).find_each do |recommendation|
        duplicate = CoachRecommendation
          .where(
            user_id: recommendation.user_id,
            exercise_id: equivalent.id,
            recommendation_type: recommendation.recommendation_type,
            status: recommendation.status
          )
          .where.not(id: recommendation.id)
          .exists?

        if duplicate
          recommendation.update!(exercise_id: nil)
          report[:recommendations_detached] += 1
        else
          recommendation.update!(exercise_id: equivalent.id)
          report[:recommendations_reassigned] += 1
        end
      end
    end

    def replace_suggestion_log_refs(old_id, new_id, report)
      current_count = ExerciseSuggestionLog.where(current_exercise_id: old_id).update_all(current_exercise_id: new_id)
      suggested_count = ExerciseSuggestionLog.where(suggested_exercise_id: old_id).update_all(suggested_exercise_id: new_id)
      report[:suggestion_logs_detached] += current_count + suggested_count if new_id.nil?
      report[:suggestion_logs_reassigned] += current_count + suggested_count if new_id.present?
    end

    def replace_profile_refs(old_id, new_id, report)
      HealthProfile.find_each do |profile|
        next unless Array(profile.avoided_exercise_ids).map(&:to_i).include?(old_id)

        profile.update_columns(avoided_exercise_ids: replace_id(Array(profile.avoided_exercise_ids), old_id, new_id))
        report[:profile_refs_updated] += 1
      end

      FitnessProfile.find_each do |profile|
        attrs = {}
        %i[preferred_exercises avoided_exercises].each do |field|
          ids = Array(profile.public_send(field))
          attrs[field] = replace_id(ids, old_id, new_id) if ids.map(&:to_i).include?(old_id)
        end
        next if attrs.empty?

        profile.update_columns(attrs)
        report[:profile_refs_updated] += 1
      end
    end

    def replace_strategy_refs(old_id, new_id, report)
      WorkoutStrategy.find_each do |strategy|
        payload = strategy.strategy.deep_dup
        changed = false
        %w[preferred_exercises avoided_exercises].each do |key|
          ids = Array(payload[key])
          next unless ids.map(&:to_i).include?(old_id)

          payload[key] = replace_id(ids, old_id, new_id)
          changed = true
        end
        next unless changed

        strategy.update_columns(strategy: payload)
        report[:strategy_refs_updated] += 1
      end
    end

    def replace_id(ids, old_id, new_id)
      ids.map { |id| id.to_i == old_id ? new_id : id }.compact.map(&:to_i).uniq
    end

    def mark_empty_days_invalid(day_ids, report)
      WorkoutDay.where(id: day_ids.to_a).find_each do |day|
        next unless day.workout_day_exercises.count.zero?

        day.update!(invalid_workout_reason: "exercises_without_gif")
        report[:workout_days_invalidated] += 1
      end
    end

    def purge_report(dry_run:, valid_count:)
      {
        dry_run: dry_run,
        valid_gifdotreino_exercises: valid_count,
        scanned: 0,
        reassigned_exercises: 0,
        destroyed_exercises: 0,
        workout_day_exercises_reassigned: 0,
        workout_day_exercises_removed: 0,
        exercise_sessions_reassigned: 0,
        exercise_sessions_removed: 0,
        favorites_reassigned: 0,
        favorites_removed: 0,
        recommendations_reassigned: 0,
        recommendations_detached: 0,
        suggestion_logs_reassigned: 0,
        suggestion_logs_detached: 0,
        profile_refs_updated: 0,
        strategy_refs_updated: 0,
        workout_days_invalidated: 0
      }
    end

    def normalize(value)
      value.to_s
        .unicode_normalize(:nfkd)
        .encode("ASCII", replace: "")
        .downcase
        .gsub(/[^a-z0-9\s]/, "")
        .squeeze(" ")
        .strip
    end

    def name_similarity(a, b)
      return 0.0 if a.blank? || b.blank?
      return 1.0 if a == b
      return 0.75 if a.include?(b) || b.include?(a)

      words_a = a.split
      words_b = b.split
      intersection = words_a & words_b
      union = words_a | words_b
      union.empty? ? 0.0 : intersection.size.to_f / union.size
    end
  end
end
