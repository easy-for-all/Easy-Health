module Ai
  class WorkoutChatTurnParser
    ALLOWED_PROFILE_FIELDS = %w[
      goal fitness_level training_days_per_week training_location
      available_equipment limitations session_duration_minutes modality
    ].freeze

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
      reply = data["reply"].to_s
      return error_result("reply vazio") if reply.blank?

      {
        valid:  true,
        errors: [],
        data:   {
          reply:              reply,
          extracted_profile:  normalize_profile(data["extracted_profile"]),
          ready_for_plan:     data["ready_for_plan"] == true
        }
      }
    end

    def normalize_profile(profile)
      return {} unless profile.is_a?(Hash)

      profile.slice(*ALLOWED_PROFILE_FIELDS).filter_map do |key, value|
        normalized = normalize_field(key, value)
        [key, normalized] unless normalized.nil?
      end.to_h
    end

    def normalize_field(key, value)
      case key
      when "goal"
        value.to_s if HealthProfile::GOALS.include?(value.to_s)
      when "fitness_level"
        value.to_s if HealthProfile::FITNESS_LEVELS.include?(value.to_s)
      when "training_days_per_week"
        Integer(value, exception: false)&.clamp(1, 6)
      when "training_location"
        value.to_s if HealthProfile::TRAINING_LOCATIONS.include?(value.to_s)
      when "available_equipment"
        Array(value).map(&:to_s).select { |v| HealthProfile::EQUIPMENT_OPTIONS.include?(v) }.presence
      when "limitations"
        Array(value).map(&:to_s).map(&:strip).reject(&:blank?).presence
      when "session_duration_minutes"
        candidate = Integer(value, exception: false)
        return nil unless candidate
        HealthProfile::SESSION_DURATIONS.min_by { |d| (d - candidate).abs }
      when "modality"
        value.to_s if HealthProfile::MODALITIES.include?(value.to_s)
      end
    end

    def error_result(message)
      { valid: false, errors: [message], data: nil }
    end
  end
end
