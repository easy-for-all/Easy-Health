module WorkoutIntelligence
  # Completes a day's exercise list when the primary muscle_group + "musculacao"
  # exercise_type query didn't return enough candidates (e.g. many core
  # exercises are classified as "funcional" rather than "musculacao" in the
  # catalog). Tries the same muscle_group under a relaxed exercise_type first,
  # then falls back to related muscle groups as a last resort.
  class TopUpFiller
    DEFAULT_FALLBACK_EXERCISE_TYPES = %w[funcional].freeze

    def fill(current_exercises:, target_count:, primary_group:, base_scope:,
             exclude_ids: [], fallback_exercise_types: DEFAULT_FALLBACK_EXERCISE_TYPES, fallback_groups: [])
      current = current_exercises.dup
      need = target_count - current.size
      return current if need <= 0

      used_ids = Array(exclude_ids) + current.map(&:id)

      same_group_relaxed = base_scope
        .where(muscle_group: primary_group, exercise_type: fallback_exercise_types)
        .where.not(id: used_ids.presence || [ 0 ])
        .to_a
      current.concat(same_group_relaxed.first(need))

      need = target_count - current.size
      return current if need <= 0 || fallback_groups.empty?

      used_ids = Array(exclude_ids) + current.map(&:id)
      related = base_scope
        .where(muscle_group: fallback_groups)
        .where.not(id: used_ids.presence || [ 0 ])
        .to_a
      current.concat(related.first(need))

      current
    end
  end
end
