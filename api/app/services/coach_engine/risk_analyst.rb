module CoachEngine
  class RiskAnalyst
    LIMITATION_RULES = {
      "knee" => {
        patterns: %w[high_impact deep_knee_flexion],
        regressions: %w[low_impact supported_lower_body_variation],
        note: "Limitações de joelho pedem impacto e amplitude progressivos."
      },
      "lower_back" => {
        patterns: %w[heavy_spinal_loading high_spinal_flexion],
        regressions: %w[supported_variation reduced_spinal_load],
        note: "Limitações lombares pedem carga axial e flexão progressivas."
      },
      "shoulder" => {
        patterns: %w[heavy_overhead_loading unstable_shoulder_loading],
        regressions: %w[supported_upper_body_variation reduced_overhead_range],
        note: "Limitações de ombro pedem controle de amplitude e estabilidade."
      },
      "wrist" => {
        patterns: %w[high_wrist_extension],
        regressions: %w[neutral_grip_variation],
        note: "Limitações de punho pedem pegadas neutras e carga progressiva."
      },
      "neck" => {
        patterns: %w[high_neck_loading],
        regressions: %w[neutral_neck_variation],
        note: "Limitações de pescoço pedem alinhamento neutro e menor carga direta."
      },
      "hip" => {
        patterns: %w[deep_hip_flexion high_impact],
        regressions: %w[controlled_range_of_motion],
        note: "Limitações de quadril pedem amplitude e impacto progressivos."
      },
      "postpartum" => {
        patterns: %w[high_impact aggressive_core_loading],
        regressions: %w[conservative_core_progression low_impact_variation],
        note: "O contexto pós-parto pede progressão conservadora e acompanhamento profissional quando necessário."
      },
      "pregnant" => {
        patterns: %w[high_impact aggressive_core_loading high_fall_risk],
        regressions: %w[low_impact_variation supported_variation conservative_core_progression],
        note: "O contexto gestacional pede progressão conservadora e acompanhamento profissional quando necessário."
      },
      "injury_return" => {
        patterns: %w[advanced_skill high_impact],
        regressions: %w[supported_variation gradual_return],
        note: "O retorno de lesão pede progressão gradual e atenção a desconforto."
      }
    }.freeze

    def initialize(user:, fitness_profile:, health_profile: nil)
      @user = user
      @fitness_profile = fitness_profile
      @health_profile = health_profile || user.health_profile
    end

    def call
      rules = matched_rules
      score = calculated_risk_score(rules)
      {
        "risk_score" => score,
        "forbidden_exercise_patterns" => forbidden_patterns(rules),
        "caution_notes" => caution_notes(rules),
        "required_regressions" => required_regressions(rules),
        "confidence" => @health_profile ? 0.8 : 0.3,
        "explanation" => "O risco usa somente nível, idade, limitações declaradas e sinais já persistidos; não é diagnóstico.",
        "evidence" => {
          "fitness_level" => @health_profile&.fitness_level,
          "age_group" => age_group,
          "limitation_categories" => rules.keys
        }
      }
    end

    private

    def calculated_risk_score(rules)
      score = @fitness_profile.risk_score.to_f
      score += 1 if @health_profile&.fitness_level == "beginner"
      score += 1 if @health_profile&.age.to_i >= 60
      score += rules.size
      score.clamp(0, 10).round(2)
    end

    def forbidden_patterns(rules)
      patterns = []
      patterns << "advanced_skill" if @health_profile&.fitness_level == "beginner"
      patterns << "high_balance_demand" if @health_profile&.age.to_i >= 60
      patterns.concat(rules.values.flat_map { |rule| rule[:patterns] })
      patterns.uniq
    end

    def caution_notes(rules)
      notes = []
      notes << "Iniciantes precisam priorizar técnica e variações menos complexas." if @health_profile&.fitness_level == "beginner"
      notes << "A idade disponível pede progressão conservadora e foco em estabilidade." if @health_profile&.age.to_i >= 60
      notes.concat(rules.values.map { |rule| rule[:note] })
      notes.uniq
    end

    def required_regressions(rules)
      regressions = []
      regressions << "supported_or_machine_variation" if @health_profile&.fitness_level == "beginner"
      regressions << "balance_supported_variation" if @health_profile&.age.to_i >= 60
      regressions.concat(rules.values.flat_map { |rule| rule[:regressions] })
      regressions.uniq
    end

    def matched_rules
      (limitation_keys + training_context_keys).uniq.each_with_object({}) do |key, rules|
        rules[key] = LIMITATION_RULES[key] if LIMITATION_RULES.key?(key)
      end
    end

    def training_context_keys
      case @health_profile&.training_context
      when "postpartum" then [ "postpartum" ]
      when "pregnant" then [ "pregnant" ]
      else []
      end
    end

    def limitation_keys
      Array(@health_profile&.limitations).filter_map do |limitation|
        normalized = I18n.transliterate(limitation.to_s).downcase
        case normalized
        when /joelho|knee/ then "knee"
        when /lombar|coluna|lower back/ then "lower_back"
        when /ombro|shoulder/ then "shoulder"
        when /punho|wrist/ then "wrist"
        when /pescoco|neck/ then "neck"
        when /quadril|hip/ then "hip"
        when /pos.?parto|postpartum/ then "postpartum"
        when /lesao|injury/ then "injury_return"
        end
      end.uniq
    end

    def age_group
      return "unknown" unless @health_profile&.age
      return "minor" if @health_profile.age < 18
      return "older_adult" if @health_profile.age >= 60

      "adult"
    end
  end
end
