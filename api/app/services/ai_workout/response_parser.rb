module AiWorkout
  class ResponseParser
    VALID_METHODS = %w[full_body upper_lower ab abc ppl custom].freeze
    VALID_GROUPS  = %w[chest back shoulders biceps triceps legs core forearms calves glutes trapezius].freeze

    def initialize(raw_response)
      @raw = raw_response
    end

    def call
      json_str = extract_json(@raw)
      return error_result("Empty or nil response") if json_str.blank?

      data = JSON.parse(json_str)
      validate_and_normalize(data)
    rescue JSON::ParserError => e
      error_result("JSON parse error: #{e.message}")
    end

    private

    def extract_json(raw)
      return nil if raw.blank?
      raw.match(/\{.*\}/m)&.to_s
    end

    def validate_and_normalize(data)
      errors = []

      method = data["training_method"].to_s
      errors << "training_method inválido: '#{method}'" unless VALID_METHODS.include?(method)

      week_struct = Array(data["week_structure"])
      errors << "week_structure vazio" if week_struct.empty?

      normalized_structure = week_struct.filter_map do |day|
        groups = Array(day["muscle_groups"]).select { |g| VALID_GROUPS.include?(g.to_s) }
        next nil if groups.empty?
        { name: day["name"].to_s.presence || "Treino", muscle_groups: groups }
      end

      errors << "week_structure sem grupos válidos" if normalized_structure.empty?

      return error_result(errors.join("; ")) if errors.any?

      sets = data["sets"].to_i.clamp(1, 8)
      reps = data["reps"].to_i.clamp(1, 30)
      rest = data["rest_seconds"].to_i.clamp(0, 300)

      {
        valid:  true,
        errors: [],
        data:   {
          training_method:      method,
          plan_name:            data["plan_name"].to_s.presence || "Plano Personalizado",
          rationale:            data["rationale"].to_s,
          personalization_reason: data["personalization_reason"].to_s,
          user_explanation:     data["user_explanation"].to_s,
          coach_notes:          data["coach_notes"].to_s,
          week_structure:       normalized_structure,
          sets_reps:            { sets: sets, reps: reps, rest_seconds: rest },
          progression_strategy: data["progression_strategy"].to_s,
          safety_notes:         Array(data["safety_notes"]).map(&:to_s)
        }
      }
    end

    def error_result(message)
      { valid: false, errors: [message], data: nil }
    end
  end
end
