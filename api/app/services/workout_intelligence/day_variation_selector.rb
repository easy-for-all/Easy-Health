module WorkoutIntelligence
  # Picks which exercises fill a muscle-group slot on a given day, avoiding
  # exercises already used earlier in the week (so repeated-group days like
  # "Push A"/"Push B" don't end up with identical exercise lists) and
  # ordering by role to vary the stimulus (compound-first vs accessory-first)
  # between those repeated days.
  class DayVariationSelector
    def initialize(fitness_level:, style_tags: [])
      @fitness_level = fitness_level
      @style_weighting = StylePreferenceWeighting.new(preferred_styles: style_tags)
    end

    def select(scope:, group:, count:, exclude_ids: [], emphasis: :balanced)
      candidates = scope.where.not(id: Array(exclude_ids).presence || [ 0 ]).to_a
      candidates = @style_weighting.sort(candidates)
      candidates = apply_emphasis(candidates, emphasis)
      candidates.first(count)
    end

    private

    def apply_emphasis(candidates, emphasis)
      return candidates unless %i[compound_first accessory_first].include?(emphasis)

      compounds, accessories = candidates.partition { |ex| ExerciseRoleClassifier.role_for(ex) == :compound }
      emphasis == :compound_first ? compounds + accessories : accessories + compounds
    end
  end
end
