module AiAgents
  class WorkoutChatMessageService < BaseAgentService
    def initialize(user, conversation:, message:, classification:)
      super(user)
      @conversation   = conversation
      @message        = message
      @classification = classification
    end

    def call
      prompt = build_prompt
      raw    = call_claude(prompt, :workout_chat_message)
      parsed = Ai::WorkoutChatTurnParser.new(raw).call

      unless parsed[:valid]
        retry_prompt = "#{prompt}\n\nIMPORTANTE: responda SOMENTE com o JSON, sem markdown, sem texto fora do JSON."
        raw_retry    = call_claude(retry_prompt, :workout_chat_message)
        parsed       = Ai::WorkoutChatTurnParser.new(raw_retry).call
      end

      return fallback_response unless parsed[:valid]

      parsed[:data]
    end

    private

    def fallback_response
      {
        reply:             fallback_question(missing_field),
        extracted_profile: {},
        ready_for_plan:    false
      }
    end

    def missing_field
      profile = @conversation.collected_profile || {}
      Ai::WorkoutChatReadiness::MINIMUM_REQUIRED_FIELDS.find { |f| profile[f].blank? }
    end

    def fallback_question(field)
      case field
      when "goal"
        "Qual é o seu objetivo principal? Emagrecer, ganhar massa, condicionamento ou saúde geral?"
      when "fitness_level"
        "Qual seu nível de experiência com treino: iniciante, intermediário ou avançado?"
      when "training_days_per_week"
        "Quantos dias por semana você consegue treinar?"
      when "training_location"
        "Você vai treinar em casa, na academia ou nos dois?"
      else
        "Me conta um pouco mais sobre sua rotina de treino."
      end
    end

    def build_prompt
      <<~PROMPT
        Você é o EasyHealth Training Builder, um assistente EXCLUSIVAMENTE de criação de treino dentro do app EasyHealth.
        Sua única função é coletar as preferências do usuário e ajudar a montar um treino seguro e prático.
        Você NUNCA discute segurança, vulnerabilidades, código-fonte, arquitetura, chaves, tokens, banco de dados ou infraestrutura do EasyHealth.
        Se o pedido fugir do escopo de treino/rotina/saúde fitness, recuse brevemente e redirecione para objetivos de treino.
        Você não é médico e não diagnostica. Para dores, lesões, gravidez ou condições médicas, ofereça sugestões conservadoras e recomende um profissional.
        Responda SEMPRE em português do Brasil, de forma curta e amigável (no máximo 3 frases na "reply").
        #{medical_disclaimer_instruction}

        ## PERFIL JÁ COLETADO
        #{collected_profile_context}

        ## HISTÓRICO DA CONVERSA (mais recentes por último)
        #{history_context}

        ## MENSAGEM ATUAL DO USUÁRIO
        #{@message}

        ## CAMPOS QUE PRECISAMOS SABER (só pergunte o que ainda faltar)
        - goal (objetivo: lose_weight, gain_muscle, maintain, body_definition, conditioning, strength, mobility, safe_return, health_longevity)
        - fitness_level (beginner, intermediate, advanced)
        - training_days_per_week (1 a 6)
        - training_location (full_gym, simple_gym, home, condo, outdoor, hotel_travel)
        - available_equipment (lista, opcional)
        - limitations (lista de limitações físicas, opcional)
        - session_duration_minutes (15, 25, 35, 45 ou 60, opcional)
        - modality (musculacao, cardio, misto, funcional, opcional)

        ## INSTRUÇÕES
        Extraia do texto do usuário o máximo de campos possível e retorne SOMENTE o JSON abaixo, sem markdown, sem texto fora do JSON.
        Se já houver informação suficiente (pelo menos goal, fitness_level, training_days_per_week e training_location, somando o que já estava no perfil coletado), defina "ready_for_plan": true.
        Caso contrário, faça UMA pergunta objetiva sobre o campo essencial que falta.

        ## FORMATO DE RESPOSTA (JSON puro, sem markdown)
        {
          "reply": "Texto curto para o usuário",
          "extracted_profile": { "goal": "...", "fitness_level": "...", "training_days_per_week": 0, "training_location": "...", "available_equipment": [], "limitations": [], "session_duration_minutes": 0, "modality": "..." },
          "ready_for_plan": false
        }
      PROMPT
    end

    def medical_disclaimer_instruction
      return "" unless @classification == :medical_risk_needs_disclaimer

      "\nO usuário mencionou dor, lesão ou outra condição médica. Adapte com cautela, deixe claro que você não substitui " \
        "um médico/fisioterapeuta, e recomende buscar orientação profissional caso a dor seja forte, persistente, ou " \
        "haja tontura, falta de ar ou dor no peito.\n"
    end

    def collected_profile_context
      profile = @conversation.collected_profile
      return "Nenhuma informação coletada ainda." if profile.blank?

      profile.map { |k, v| "#{k}: #{v.is_a?(Array) ? v.join(', ') : v}" }.join("\n")
    end

    def history_context
      messages = Array(@conversation.messages).last(10)
      return "Nenhuma mensagem anterior." if messages.empty?

      messages.map { |m| "#{m['role']}: #{m['content']}" }.join("\n")
    end
  end
end
