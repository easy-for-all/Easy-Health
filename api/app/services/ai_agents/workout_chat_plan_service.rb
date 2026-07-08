module AiAgents
  class WorkoutChatPlanService < BaseAgentService
    def initialize(user, collected_profile:, previous_preview: nil, adjust_instruction: nil)
      super(user)
      @collected_profile  = collected_profile || {}
      @previous_preview   = previous_preview
      @adjust_instruction = adjust_instruction
    end

    def call
      raw    = call_claude(build_prompt, :workout_chat_plan_generation)
      result = AiWorkout::ResponseParser.new(raw).call

      unless result[:valid]
        retry_prompt = "#{build_prompt}\n\nERROS NA RESPOSTA ANTERIOR: #{result[:errors].join('; ')}\n" \
                        "Corrija e responda SOMENTE com o JSON, sem markdown."
        raw    = call_claude(retry_prompt, :workout_chat_plan_generation)
        result = AiWorkout::ResponseParser.new(raw).call
      end

      return fallback_result unless result[:valid]

      safety = AiWorkout::SafetyValidator.new(
        parsed_data:     result[:data],
        fitness_profile: @user.fitness_profile
      ).call

      return fallback_result if safety[:violations].any?

      data = result[:data].dup
      data[:safety_notes] = (Array(data[:safety_notes]) + Array(safety[:warnings])).uniq

      { valid: true, fallback: false, fallback_reason: nil, data: data }
    end

    private

    def fallback_result
      AiWorkout::FallbackGenerator.new(
        user:          @user,
        days_per_week: days_per_week,
        reason:        "workout_chat_ai_failure"
      ).call
    end

    def build_prompt
      @adjust_instruction.present? ? build_adjust_prompt : build_generate_prompt
    end

    def build_generate_prompt
      <<~PROMPT
        Você é um especialista em prescrição de treino personalizado do EasyHealth.
        Analise o perfil coletado no chat abaixo e retorne SOMENTE um JSON válido, sem texto adicional, sem markdown.

        ## PERFIL COLETADO NO CHAT
        - Objetivo: #{profile_value('goal') || 'não informado'}
        - Nível: #{profile_value('fitness_level') || 'beginner'}
        - Dias por semana: #{days_per_week}
        - Local de treino: #{profile_value('training_location') || 'full_gym'}
        - Equipamentos disponíveis: #{Array(profile_value('available_equipment')).join(', ').presence || 'não informado'}
        - Limitações físicas: #{Array(profile_value('limitations')).join(', ').presence || 'nenhuma'}
        - Duração da sessão: #{profile_value('session_duration_minutes') || 'não informada'}
        - Modalidade preferida: #{profile_value('modality') || 'musculacao'}

        ## INSTRUÇÕES
        Métodos válidos: #{AiWorkout::ResponseParser::VALID_METHODS.join(', ')}.
        Grupos musculares válidos: #{AiWorkout::ResponseParser::VALID_GROUPS.join(', ')}.
        Número de dias no week_structure: exatamente #{days_per_week}.
        Cada dia deve ter entre 2 e 5 muscle_groups.
        Não exagere volume para iniciantes (máx 3 exercícios por grupo muscular).
        Nunca coloque o mesmo grupo muscular em dias consecutivos sem recuperação.
        Se houver limitações físicas, adapte a intensidade e inclua orientação nas safety_notes, recomendando avaliação profissional se a limitação for séria.
        Se o objetivo for emagrecimento ou condicionamento, inclua sugestão de cardio nas safety_notes.

        ## FORMATO DE RESPOSTA (JSON puro, sem markdown)
        {
          "training_method": "upper_lower",
          "plan_name": "Plano Hipertrofia — Superior/Inferior",
          "rationale": "Explicação em português de por que este método foi escolhido para este perfil (2-3 frases)",
          "week_structure": [
            { "name": "Superior A", "muscle_groups": ["chest", "back", "shoulders"] },
            { "name": "Inferior",   "muscle_groups": ["legs", "core"] }
          ],
          "sets": 3,
          "reps": 10,
          "rest_seconds": 90,
          "progression_strategy": "Semana 1: adaptação com foco em técnica. Semana 2: aumentar 1 repetição por série. Semana 3: aumentar carga em 5-10%. Semana 4: deload leve.",
          "safety_notes": ["Aquecer 5-10 min antes de cada treino", "Descansar 48h antes de treinar o mesmo grupo muscular"]
        }
      PROMPT
    end

    def build_adjust_prompt
      <<~PROMPT
        #{build_generate_prompt}

        ## PRÉVIA ANTERIOR (JSON)
        #{@previous_preview.to_json}

        ## PEDIDO DE AJUSTE DO USUÁRIO
        #{@adjust_instruction}

        Gere uma NOVA versão completa do JSON (não um diff), aplicando o pedido de ajuste acima e mantendo o mesmo formato de resposta.
      PROMPT
    end

    def profile_value(key)
      @collected_profile[key] || @collected_profile[key.to_sym]
    end

    def days_per_week
      (profile_value("training_days_per_week") || 3).to_i.clamp(1, 6)
    end
  end
end
