module WorkoutIntelligence
  # Weighs (never filters) a list of exercises toward the user's preferred
  # training styles (e.g. "calisthenics"). Applied AFTER the safety/level
  # filter, so a calisthenics preference can never reintroduce an exercise
  # that was blocked by TechnicalLevelPolicy — it only reorders what already
  # passed the safety gate.
  class StylePreferenceWeighting
    def initialize(preferred_styles: [])
      @preferred_styles = Array(preferred_styles)
    end

    def sort(exercises)
      return exercises if @preferred_styles.empty?

      preferred, rest = exercises.partition { |ex| (Array(ex.style_tags) & @preferred_styles).any? }
      preferred + rest
    end
  end
end
