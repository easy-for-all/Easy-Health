module AiWorkout
  class SafetyValidator
    HIGH_RISK_PERSONAS      = %w[sedentary_beginner hypertrophy_beginner weight_loss_beginner
                                  older_adult_mobility obese_weight_loss postpartum_return
                                  rehabilitation_return].freeze
    MAX_SETS_PER_EXERCISE   = 8
    MAX_EXERCISES_PER_DAY   = 15

    # safety_tags on exercises that map to forbidden patterns
    LIMITATION_TAG_MAP = {
      "high_impact"           => %w[knee hip postpartum pregnant injury_return],
      "deep_knee_flexion"     => %w[knee],
      "heavy_spinal_loading"  => %w[lower_back],
      "high_spinal_flexion"   => %w[lower_back],
      "heavy_overhead_loading" => %w[shoulder],
      "unstable_shoulder_loading" => %w[shoulder],
      "high_wrist_extension"  => %w[wrist],
      "high_neck_loading"     => %w[neck],
      "deep_hip_flexion"      => %w[hip],
      "aggressive_core_loading" => %w[postpartum pregnant],
      "advanced_skill"        => %w[beginner]
    }.freeze

    def initialize(parsed_data:, fitness_profile:, workout_strategy: nil)
      @data             = parsed_data
      @fitness_profile  = fitness_profile
      @workout_strategy = workout_strategy
      @violations       = []
      @warnings         = []
    end

    def call
      return skip_result unless @data.present?

      check_week_structure
      check_volume
      check_forbidden_patterns
      check_intensity_vs_risk
      check_warmup_requirement

      {
        valid:      @violations.empty?,
        violations: @violations,
        warnings:   @warnings
      }
    end

    private

    def check_week_structure
      Array(@data[:week_structure] || @data["week_structure"]).each do |day|
        exercises_in_day = day[:exercises] || day["exercises"] || []
        if exercises_in_day.size > MAX_EXERCISES_PER_DAY
          @violations << "Dia '#{day[:name] || day['name']}' tem #{exercises_in_day.size} exercícios (máximo #{MAX_EXERCISES_PER_DAY})"
        end
      end
    end

    def check_volume
      sets = (@data[:sets_reps] || @data["sets_reps"] || {})[:sets] ||
             (@data[:sets_reps] || @data["sets_reps"] || {})["sets"] || 0

      if sets.to_i > MAX_SETS_PER_EXERCISE
        @violations << "Volume excessivo: #{sets} séries por exercício (máximo #{MAX_SETS_PER_EXERCISE})"
      end
    end

    def check_forbidden_patterns
      return unless @fitness_profile

      forbidden = forbidden_patterns_for_user
      return if forbidden.empty?

      @warnings << "Padrões proibidos para este usuário: #{forbidden.join(', ')}. Verifique os exercícios gerados."
    end

    def check_intensity_vs_risk
      return unless @fitness_profile
      risk_score = @fitness_profile.risk_score.to_f
      return unless risk_score >= 7

      intensity = @data[:intensity_level] || @data["intensity_level"] || extract_intensity_from_strategy
      if intensity == "high"
        @violations << "Intensidade 'high' não permitida para risk_score >= 7 (atual: #{format('%.1f', risk_score)})"
      elsif intensity == "moderate"
        @warnings << "Intensidade 'moderate' com risk_score alto (#{format('%.1f', risk_score)}). Monitore o usuário."
      end
    end

    def check_warmup_requirement
      return unless @fitness_profile
      return unless high_risk_persona?
      return unless @fitness_profile.risk_score.to_f >= 5

      safety_notes = Array(@data[:safety_notes] || @data["safety_notes"])
      has_warmup_note = safety_notes.any? { |n| n.downcase.include?("aquec") || n.downcase.include?("aqueç") || n.downcase.include?("warm") }
      @warnings << "Persona de risco alto sem nota de aquecimento explícita nas safety_notes" unless has_warmup_note
    end

    def high_risk_persona?
      HIGH_RISK_PERSONAS.include?(@fitness_profile.primary_persona.to_s)
    end

    def forbidden_patterns_for_user
      return [] unless @fitness_profile

      patterns = []
      patterns << "advanced_skill" if high_risk_persona?

      limitations = Array(@fitness_profile.physical_limitations).map(&:to_s).map(&:downcase)
      LIMITATION_TAG_MAP.each do |pattern, affected|
        if affected.any? { |a| limitations.any? { |l| l.include?(a) } }
          patterns << pattern
        end
      end

      patterns.uniq
    end

    def extract_intensity_from_strategy
      return nil unless @workout_strategy
      strategy = @workout_strategy.is_a?(WorkoutStrategy) ? @workout_strategy.strategy : @workout_strategy
      strategy&.dig("intensity_level")
    end

    def skip_result
      { valid: true, violations: [], warnings: [] }
    end
  end
end
