module WorkoutIntelligence
  # Fuzzy name matching used to resolve curated exercise names (accents/casing
  # may vary) against the live `exercises` table without hardcoding ids.
  class NameMatcher
    MIN_SCORE = 0.5

    def self.normalize(text)
      text.to_s
          .unicode_normalize(:nfkd)
          .gsub(/[^\x00-\x7F]/, "")
          .downcase
          .gsub(/[^a-z0-9\s]/, " ")
          .squish
    end

    def self.best_match(target_name, scope = Exercise.all)
      normalized_target = normalize(target_name)
      return nil if normalized_target.blank?

      exact = scope.find { |ex| normalize(ex.name) == normalized_target }
      return exact if exact

      target_tokens = normalized_target.split.to_set
      return nil if target_tokens.empty?

      best = nil
      best_score = 0.0

      scope.each do |ex|
        candidate_tokens = normalize(ex.name).split.to_set
        next if candidate_tokens.empty?

        overlap = (target_tokens & candidate_tokens).size.to_f
        union   = (target_tokens | candidate_tokens).size.to_f
        score   = union.zero? ? 0.0 : overlap / union

        if score > best_score
          best_score = score
          best = ex
        end
      end

      best_score >= MIN_SCORE ? best : nil
    end
  end
end
